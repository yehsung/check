// W3-c3 울트라 구매 페이지 — 맥 WorkTimerStoreAuth.swift 645-720(고르기 → 구매하기 · canConfirm) · 805-846(buyUltra) 규칙을 MockEngine 녹음으로 잰다.
package com.yehsung.aingcheck.desktop.pages.ultra

import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.ultra.UltraPurchase
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletState
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
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
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class UltraPurchasePageTest {
    private class Rig(scope: TestScope, ruby: Long?, var price: Long? = 30, walletBalance: Long? = 2) {
        val server = FakeServer(scope)
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        val rubyCell = RubyBalanceCell(ruby)
        var shopMutations = 0
        val wallet = UltraWalletStore(
            host, FakeWorkState(), NO_LAPS, UltraChargedSink { }, scope, clock::now,
            initial = UltraWalletState(balance = walletBalance),
        )
        val purchase = UltraPurchase(host, rubyCell, wallet, scope, { price }, { shopMutations += 1 })
        var shopReloads = 0
        val model = UltraPurchaseModel(purchase, rubyCell, { price }, reloadShop = { shopReloads += 1 })
    }

    @Test
    fun `진행 중 두 번째 누름은 무시 — buy_ultra 1건 · 본문 p_count 1`() = runTest {
        val gate = CompletableDeferred<Unit>()
        val r = Rig(this, ruby = 100)
        r.server.on("POST", BUY_PATH, Reply.Hold(gate, Reply.Json("""{"status":"ok","ultra_balance":3,"ruby_balance":70}""")))
        r.model.select()
        assertTrue(r.model.canConfirm())
        assertTrue(r.model.confirm() != null)
        runCurrent()
        // 날아가는 중: 다시 눌러도·고르기를 풀려 해도 아무 일 없다.
        assertNull(r.model.confirm(), "진행 중 두 번째 [구매하기]가 요청을 냈다")
        r.model.select()
        assertTrue(r.model.selected.value, "진행 중 고르기가 풀렸다")
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, r.server.count("POST", BUY_PATH), "buy_ultra 요청 수")
        val body = Json.parseToJsonElement(r.server.bodies("POST", BUY_PATH).single()).jsonObject
        assertEquals(1, body.getValue("p_count").jsonPrimitive.int)
        assertEquals(setOf("p_count"), body.keys)
    }

    @Test
    fun `성공 뒤 잔액은 서버 응답 값 — 앞질러 빼지 않는다 · 고른 것이 풀린다`() = runTest {
        val gate = CompletableDeferred<Unit>()
        val r = Rig(this, ruby = 100)
        // 일부러 '100 − 30 = 70' 과 다른 값 — 클라가 빼면 70, 서버 값이면 65.
        r.server.on("POST", BUY_PATH, Reply.Hold(gate, Reply.Json("""{"status":"ok","ultra_balance":4,"ruby_balance":65}""")))
        r.model.select()
        r.model.confirm()
        runCurrent()
        assertEquals(100L, r.rubyCell.rubyBalance, "응답 전에 루비를 뺐다")
        assertEquals(2L, r.wallet.state.value.balance, "응답 전에 울트라를 더했다")
        assertTrue(r.model.isPurchasing.value)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(65L, r.rubyCell.rubyBalance)
        assertEquals(4L, r.wallet.state.value.balance)
        assertEquals("울트라 1개를 샀어요!", r.model.notice.value)
        assertEquals(UltraShopText.okNotice(1), r.model.notice.value, "ok 문구가 UltraPurchase 와 갈렸다")
        assertFalse(r.model.selected.value, "ok 뒤 고른 것이 남았다(맥 shopSelection = nil)")
        assertFalse(r.model.isPurchasing.value)
        assertEquals(1, r.shopMutations, "상점 상태 재조회 이유(noteShopMutation) 1번")
    }

    @Test
    fun `루비 부족 — 서버 insufficient 는 맥 문구 · 로컬로 모자라면 요청 0건`() = runTest {
        val r = Rig(this, ruby = 100)
        r.server.on("POST", BUY_PATH, Reply.Json("""{"status":"insufficient","need":30,"have":10,"ruby_balance":10}"""))
        r.model.select()
        r.model.confirm()
        advanceUntilIdle()
        assertEquals("루비 20개 더 필요해요", r.model.notice.value)
        assertEquals(10L, r.rubyCell.rubyBalance, "서버가 준 잔액을 적는다")
        assertTrue(r.model.selected.value, "모자람은 고른 것을 풀지 않는다")
        // 이제 로컬 잔액 10 < 값 30 — 단추가 흐리고 눌러도 0건, 바는 모자란 양을 말한다.
        r.model.select() // 풀기
        r.model.select() // 다시 고르기(안내가 지워진다)
        assertNull(r.model.notice.value)
        assertFalse(r.model.canConfirm())
        assertNull(r.model.confirm())
        assertEquals(1, r.server.count("POST", BUY_PATH))
        assertEquals("루비 20개 더 필요해요", UltraShopText.barDetail(null, selected = true, price = 30, balance = 10))
    }

    @Test
    fun `로그아웃 — 고른 것·안내 한 줄이 풀린다(음성 대조 — 안 부르면 남는다)`() = runTest {
        val r = Rig(this, ruby = 100)
        r.server.on("POST", BUY_PATH, Reply.Json("""{"message":"boom"}""", 500))
        r.model.select()
        r.model.confirm()
        advanceUntilIdle()
        // 음성 대조: 실패 뒤엔 고름과 안내가 그대로 남는다(다시 누를 수 있게) — 이 상태가 다음 계정에 넘어가면 안 된다.
        assertTrue(r.model.selected.value, "전제: 실패 뒤 고름이 남아 있어야 리셋을 잰다")
        assertEquals("구매 실패", r.model.notice.value)
        r.model.resetForSignOut()
        assertFalse(r.model.selected.value, "로그아웃 뒤에도 고른 것이 남았다")
        assertNull(r.model.notice.value, "로그아웃 뒤에도 앞 계정 안내가 남았다")
        assertFalse(r.model.canConfirm())
        assertEquals(1, r.server.count("POST", BUY_PATH), "리셋이 요청을 냈다")
    }

    @Test
    fun `PagesWiring onSignedOut — 울트라 고름을 푼다 · ultra 꺼짐(페이지 없음)이면 아무 일 없음`() = runTest {
        val r = Rig(this, ruby = 100)
        fun wiring(ultra: Boolean) = com.yehsung.aingcheck.desktop.wiring.PagesWiring(
            com.yehsung.aingcheck.desktop.wiring.PagesWiringDeps(
                desktopConfig = com.yehsung.aingcheck.feature.desktop.DesktopAppConfig(ultra = ultra),
                settings = com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore(com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore()),
                wallNow = r.clock::now,
                ultra = com.yehsung.aingcheck.desktop.wiring.UltraPageInputs(wallet = r.wallet, purchase = r.purchase, ruby = r.rubyCell),
                ultraPrice = { 30L },
            ),
        )
        val on = wiring(ultra = true)
        val model = requireNotNull(on.ultraPage?.purchase)
        model.select()
        assertTrue(model.selected.value)
        on.onSignedOut()
        assertFalse(model.selected.value, "onSignedOut 이 울트라 고름을 풀지 않았다")
        val off = wiring(ultra = false)
        assertNull(off.ultraPage)
        off.onSignedOut()
        assertEquals(0, r.server.calls.size)
    }

    @Test
    fun `서버 오류 — 구매 실패 · 잔액 그대로`() = runTest {
        val r = Rig(this, ruby = 100)
        r.server.on("POST", BUY_PATH, Reply.Json("""{"message":"boom"}""", 500))
        r.model.select()
        r.model.confirm()
        advanceUntilIdle()
        assertEquals("구매 실패", r.model.notice.value)
        assertEquals(100L, r.rubyCell.rubyBalance)
        assertEquals(2L, r.wallet.state.value.balance)
        assertFalse(r.model.isPurchasing.value)
    }

    @Test
    fun `값이나 잔액을 모르면 살 수 없다 · 안 고르면 살 수 없다`() = runTest {
        val unknownPrice = Rig(this, ruby = 100, price = null)
        unknownPrice.model.select()
        assertFalse(unknownPrice.model.canConfirm())
        val unknownRuby = Rig(this, ruby = null)
        unknownRuby.model.select()
        assertFalse(unknownRuby.model.canConfirm())
        val notPicked = Rig(this, ruby = 100)
        assertFalse(notPicked.model.canConfirm())
        assertNull(notPicked.model.confirm())
        advanceUntilIdle()
        assertEquals(0, unknownPrice.server.count("POST", BUY_PATH) + unknownRuby.server.count("POST", BUY_PATH) + notPicked.server.count("POST", BUY_PATH))
    }

    @Test
    fun `문구 — 맥 UltraPanelCopy · ShopText 그대로`() {
        assertEquals("무제한", UltraPageCopy.balanceText(5, unlimited = true))
        assertEquals("—", UltraPageCopy.balanceText(null))
        assertEquals("0", UltraPageCopy.balanceText(-3))
        // 무제한 > 실패 > 모름 > 있음/없음
        assertEquals("3초 꾹 누르면 발사 — 잔량을 쓰지 않아요", UltraPageCopy.heroCaption(null, hasFailed = true, unlimited = true))
        assertEquals("최신 잔량을 못 읽었어요", UltraPageCopy.heroCaption(4, hasFailed = true))
        assertEquals("불러오는 중…", UltraPageCopy.heroCaption(null, hasFailed = false))
        assertEquals("3초 꾹 누르면 한 개 써요", UltraPageCopy.heroCaption(1, hasFailed = false))
        assertEquals("상점에서 루비로 사요", UltraPageCopy.heroCaption(0, hasFailed = false))
        assertEquals("울트라 찌르기", UltraShopText.rowTitle(null))
        assertEquals("울트라 찌르기 1개", UltraShopText.rowTitle(30))
        assertEquals("보유 —", UltraShopText.held(null))
        assertEquals("보유 0개", UltraShopText.held(-1))
        assertEquals("살 것을 골라 주세요", UltraShopText.barTitle(false))
        // 안내 > 모자람 > 빈칸(높이 고정)
        assertEquals("울트라 1개를 샀어요!", UltraShopText.barDetail("울트라 1개를 샀어요!", true, 30, 10))
        assertEquals(" ", UltraShopText.barDetail(null, true, 30, 30))
        assertEquals(" ", UltraShopText.barDetail(null, false, 30, 10))
    }
}
