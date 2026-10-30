// W3-c3 수정(반박 검증 P1·P2·P3) — 페이지 Content 를 오프스크린 ImageComposeScene 에 실제로 띄워 잰다(모델·손으로 만든 상태가 아니라).
// 맥 대조: CheckMenuView.swift 4031-4053(canPoke — startedAt 관찰값으로 바로 바뀐다) · WorkTimerStore.swift 303·310(다시 열기 = 디렉터리만,
// 지갑 panelOpen 은 미션·울트라 화면만) · 2853-2856(콕 패널 진입 = 디렉터리 + 지갑) · 3022(상점 진입 = loadShopState)
// · WorkTimerStoreAuth.swift 736-744(값·잔량을 모르면 사지 않고 상점을 다시 읽는다). 창 0 · 네트워크 0(MockEngine).
package com.yehsung.aingcheck.desktop.pages.poke

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.ultra.DIRECTORY_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.FakeServer
import com.yehsung.aingcheck.desktop.pages.ultra.FakeSessionHost
import com.yehsung.aingcheck.desktop.pages.ultra.FakeWorkState
import com.yehsung.aingcheck.desktop.pages.ultra.BUY_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.NO_LAPS
import com.yehsung.aingcheck.desktop.pages.ultra.Reply
import com.yehsung.aingcheck.desktop.pages.ultra.TestClock
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPage
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPageDeps
import com.yehsung.aingcheck.desktop.pages.ultra.UltraPurchaseModel
import com.yehsung.aingcheck.desktop.pages.ultra.WALLET_PATH
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeSender
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraWalletTrigger
import com.yehsung.aingcheck.feature.desktop.ultra.UltraPurchase
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletState
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.jetbrains.skia.Bitmap
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val A = "00000000-0000-4000-8000-00000000000a" // 근무중
private const val B = "00000000-0000-4000-8000-00000000000b" // 자리비움
private const val C = "00000000-0000-4000-8000-00000000000c" // 근무중(차단 대상)

private val DIRECTORY = """
    [
      {"user_id":"$A","display_name":"라온","is_working":true},
      {"user_id":"$B","display_name":"나비","is_working":false},
      {"user_id":"$C","display_name":"가람","is_working":true}
    ]
""".trimIndent()

private const val W_DIP = 360
private const val H_DIP = 420

/** 플라이아웃 한 장(SharedFlyoutPageHost 처럼 route 로 고른다 — 다른 route 면 페이지가 컴포지션을 떠난다). */
@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
private class Stage(private val scope: TestScope, nav: FlyoutNavigator, pages: Map<FlyoutRoute, FlyoutPageHost>) : AutoCloseable {
    private val scene = ImageComposeScene(W_DIP, H_DIP, Density(1f)) {
        AingTheme(dark = false) {
            val route by nav.route.collectAsState()
            pages[route]?.Content(nav, W_DIP.toDouble())
        }
    }
    private var t = 0L

    /** 상태 적용 → 디스패치 → 그리기를 [n] 번. 마지막 장의 픽셀. */
    fun frames(n: Int = 6): IntArray {
        var last: IntArray? = null
        repeat(n) {
            Snapshot.sendApplyNotifications()
            scope.testScheduler.runCurrent()
            val image = scene.render(t)
            t += 16_666_667L
            val bitmap = Bitmap.makeFromImage(image)
            last = IntArray(W_DIP * H_DIP) { i -> bitmap.getColor(i % W_DIP, i / W_DIP) }
            bitmap.close()
            image.close()
            scope.testScheduler.runCurrent()
        }
        return requireNotNull(last)
    }

    override fun close() = scene.close()
}

private fun diff(a: IntArray, b: IntArray): Int = a.indices.count { a[it] != b[it] }

@OptIn(ExperimentalCoroutinesApi::class)
class SocialPagesLiveTest {
    /** 콕 목록 한 벌. 입력은 Compose 상태(메시지 스토어 꼴) 또는 StateFlow(근무 스냅숏 꼴). */
    private class PokeRig(
        scope: TestScope,
        server: FakeServer,
        working: Boolean,
        hidden: Set<String> = emptySet(),
        notice: String? = null,
        val work: FakeWorkState = FakeWorkState(working),
        withWallet: Boolean = false,
    ) {
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        /** Compose 상태 출처(MessagesStore 는 mutableStateOf 로 산다). */
        val sessionOpen = mutableStateOf(working)
        val hiddenState = mutableStateOf(hidden)
        val noticeState = mutableStateOf(notice)
        var useWorkFlow = false
        val wallet: UltraWalletStore? = if (withWallet) {
            UltraWalletStore(host, FakeWorkState(), NO_LAPS, UltraChargedSink { }, scope, clock::now, initial = UltraWalletState(balance = 2))
        } else {
            null
        }
        private val open: () -> Boolean = { if (useWorkFlow) work.state.value.startedAt != null else sessionOpen.value }
        val sender = DesktopPokeSender(host, scope, clock::now, localSessionOpen = open, wallet = UltraWalletTrigger { })
        val page = PokeListPage(
            PokeListDeps(
                host = host, config = DesktopAppConfig(poke = true, ultra = true), sender = sender, wallet = wallet, focus = null, scope = scope,
                clock = clock::now, localSessionOpen = open, workChanges = work.snapshot,
                hiddenBlockedPeerIDs = { hiddenState.value }, messageNotice = { noticeState.value },
                clockTickMillis = 3_600_000L, // 1초 박자가 낡은 값을 덮어 주지 못하게(반응 경로만 잰다)
            ),
        )
    }

    private fun pokeShot(scope: TestScope, server: FakeServer, rig: PokeRig): IntArray {
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.PokeList).also { it.open() }
        Stage(scope, nav, mapOf(FlyoutRoute.PokeList to rig.page)).use { return it.frames(8) }
    }

    @Test
    fun `P1 근무를 연 채로 시작하면 단추가 바로 산다 — Compose 상태 출처`() = runTest {
        val server = FakeServer(this).on("POST", DIRECTORY_PATH, Reply.Json(DIRECTORY))
        val off = pokeShot(this, server, PokeRig(this, server, working = false))
        val fresh = pokeShot(this, server, PokeRig(this, server, working = true))
        assertTrue(diff(off, fresh) > 0, "기준선이 같다 — 근무 여부가 화면에 안 드러난다")

        val live = PokeRig(this, server, working = false)
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.PokeList).also { it.open() }
        Stage(this, nav, mapOf(FlyoutRoute.PokeList to live.page)).use { stage ->
            assertEquals(0, diff(stage.frames(8), off), "꺼짐으로 연 화면이 꺼짐 기준과 다르다")
            live.sessionOpen.value = true
            val after = stage.frames(8)
            assertEquals(PokeButtonState.READY, live.page.model.buttonState(live.page.model.rows().first { it.userID == A }, live.clock.now()))
            assertEquals(0, diff(after, fresh), "근무 시작 뒤에도 화면이 낡았다(처음부터 근무 중으로 연 화면과 ${diff(after, fresh)}픽셀 다름)")
        }
    }

    @Test
    fun `P1 근무 스냅숏(StateFlow)이 바뀌면 다시 읽는다 — 조립 꼴`() = runTest {
        val server = FakeServer(this).on("POST", DIRECTORY_PATH, Reply.Json(DIRECTORY))
        val fresh = pokeShot(this, server, PokeRig(this, server, working = true))
        val live = PokeRig(this, server, working = false).also { it.useWorkFlow = true }
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.PokeList).also { it.open() }
        Stage(this, nav, mapOf(FlyoutRoute.PokeList to live.page)).use { stage ->
            val before = stage.frames(8)
            assertTrue(diff(before, fresh) > 0, "근무 밖인데 근무 중 화면과 같다")
            live.work.state.value = DesktopWorkSnapshot(isWorking = true, startedAt = SwiftDate(1_793_000_000.0))
            assertEquals(0, diff(stage.frames(8), fresh), "근무 스냅숏이 바뀌었는데 단추가 흐린 채다")
        }
    }

    @Test
    fun `P1 차단 숨김·메시지 안내가 바뀌면 바로 따라온다`() = runTest {
        val server = FakeServer(this).on("POST", DIRECTORY_PATH, Reply.Json(DIRECTORY))
        val fresh = pokeShot(this, server, PokeRig(this, server, working = true, hidden = setOf(C), notice = "차단했어요"))
        val live = PokeRig(this, server, working = true)
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.PokeList).also { it.open() }
        Stage(this, nav, mapOf(FlyoutRoute.PokeList to live.page)).use { stage ->
            assertTrue(diff(stage.frames(8), fresh) > 0, "기준선이 같다")
            live.hiddenState.value = setOf(C)
            live.noticeState.value = "차단했어요"
            assertEquals(0, diff(stage.frames(8), fresh), "차단 숨김·안내가 화면에 안 닿았다")
            assertFalse(C in live.page.model.rows().map { it.userID })
        }
    }

    @Test
    fun `P2 콕 목록을 띄운 채 다시 열면 디렉터리만 — 지갑 sync 는 진입마다 1건`() = runTest {
        val server = FakeServer(this).on("POST", DIRECTORY_PATH, Reply.Json(DIRECTORY))
        val rig = PokeRig(this, server, working = true, withWallet = true)
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.PokeList)
        Stage(this, nav, mapOf(FlyoutRoute.PokeList to rig.page)).use { stage ->
            nav.open()
            stage.frames()
            assertEquals(1, server.count("POST", WALLET_PATH), "진입 지갑 sync")
            assertEquals(1, server.count("POST", DIRECTORY_PATH), "진입 디렉터리")
            repeat(3) {
                nav.hide()
                stage.frames()
                nav.open()
                stage.frames()
            }
            assertEquals(1, server.count("POST", WALLET_PATH), "다시 열 때마다 ultra_wallet_sync(적립 쓰기)가 늘었다 — 맥 WorkTimerStore.swift:303·310")
            assertEquals(4, server.count("POST", DIRECTORY_PATH), "다시 열 때 디렉터리를 안 읽었다(맥 :303)")
            // 홈으로 나갔다 다시 들어오면 새 진입(맥 togglePokePanel 2853-2856).
            nav.navigate(FlyoutRoute.Home)
            stage.frames()
            nav.navigate(FlyoutRoute.PokeList)
            stage.frames()
            assertEquals(2, server.count("POST", WALLET_PATH), "다시 들어온 진입에 지갑 sync 가 없다")
            assertEquals(5, server.count("POST", DIRECTORY_PATH))
        }
    }

    /** 울트라 페이지 한 벌. 값은 Compose 상태(MeStore.ultraPrice 꼴), 루비는 상점과 같은 칸. */
    private class UltraRig(scope: TestScope, server: FakeServer, ruby: Long?, price: Long?) {
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        val rubyCell = RubyBalanceCell(ruby)
        val priceState = mutableStateOf(price)
        var shopReloads = 0
        val wallet = UltraWalletStore(host, FakeWorkState(), NO_LAPS, UltraChargedSink { }, scope, clock::now, initial = UltraWalletState(balance = 2))
        val purchase = UltraPurchase(host, rubyCell, wallet, scope, { priceState.value }, { })
        val model = UltraPurchaseModel(purchase, rubyCell, { priceState.value }, reloadShop = { shopReloads += 1 })
        val page = UltraPage(UltraPageDeps(wallet = wallet, purchase = model, ruby = rubyCell, ultraPrice = { priceState.value }))
    }

    @Test
    fun `P3 울트라 화면에 들어오면 상점을 읽는다 — 다시 열기는 지갑만`() = runTest {
        val server = FakeServer(this)
        val rig = UltraRig(this, server, ruby = null, price = null)
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Ultra)
        Stage(this, nav, mapOf(FlyoutRoute.Ultra to rig.page)).use { stage ->
            nav.open()
            stage.frames()
            assertEquals(1, rig.shopReloads, "울트라 구매 화면 진입에 상점 읽기가 없다(맥 상점 진입 WorkTimerStore.swift:3022)")
            assertEquals(1, server.count("POST", WALLET_PATH), "진입 지갑 sync(맥 openUltraPanel 2880)")
            nav.hide()
            stage.frames()
            nav.open()
            stage.frames()
            assertEquals(1, rig.shopReloads, "다시 열기가 상점을 또 읽었다(맥 setMenuPresented 는 상점을 안 읽는다)")
            assertEquals(2, server.count("POST", WALLET_PATH), "다시 열기 지갑 sync(맥 :310 울트라 화면)")
        }
    }

    @Test
    fun `P3 값·루비를 모르는 채 구매하기 — 사지 않고 상점을 다시 읽는다`() = runTest {
        val server = FakeServer(this)
        val rig = UltraRig(this, server, ruby = null, price = null)
        rig.model.select()
        assertNull(rig.model.confirm())
        assertEquals(1, rig.shopReloads, "값을 모르는 [구매하기]가 상점을 다시 안 읽었다(맥 WorkTimerStoreAuth.swift:736-744)")
        rig.rubyCell.rubyBalance = 100
        assertNull(rig.model.confirm())
        assertEquals(2, rig.shopReloads, "루비만 알고 값은 모르는데 다시 안 읽었다")
        testScheduler.runCurrent()
        assertEquals(0, server.count("POST", BUY_PATH), "모르는 채 샀다")
        // 고르지 않았으면 아무 일 없다(맥 canConfirm 의 첫 가드).
        rig.model.select()
        assertNull(rig.model.confirm())
        assertEquals(2, rig.shopReloads)
    }

    @Test
    fun `P3 값이 늦게 와도 구매 단추가 산다 — 처음부터 값을 안 화면과 같은 픽셀`() = runTest {
        val server = FakeServer(this)
        val known = UltraRig(this, server, ruby = 100, price = 30).also { it.model.select() }
        val freshNav = InMemoryFlyoutNavigator(FlyoutRoute.Ultra).also { it.open() }
        val fresh = Stage(this, freshNav, mapOf(FlyoutRoute.Ultra to known.page)).use { it.frames(8) }

        // 루비는 처음부터 안다 — 값만 늦게 온다(루비 칸이 같이 바뀌어 덩달아 다시 그려지는 것을 빼고 값의 반응만 잰다).
        val late = UltraRig(this, server, ruby = 100, price = null).also { it.model.select() }
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Ultra).also { it.open() }
        Stage(this, nav, mapOf(FlyoutRoute.Ultra to late.page)).use { stage ->
            assertTrue(diff(stage.frames(8), fresh) > 0, "기준선이 같다 — 값 모름이 화면에 안 드러난다")
            assertFalse(late.model.canConfirm())
            // 상점 조회가 도착(MeStore.applyShopState 가 값을, applyShopRubyBalance 가 루비를 적는다).
            late.priceState.value = 30
            val after = stage.frames(8)
            assertTrue(late.model.canConfirm())
            assertEquals(0, diff(after, fresh), "값·루비가 왔는데 구매 단추가 흐린 채다(${diff(after, fresh)}픽셀 다름)")
        }
    }
}
