// W3-c3 콕 목록 — 맥 CheckMenuView.swift 4031-4053(단추 네 갈래) · WorkTimerStoreBlocks.swift 130-134(차단 숨김) · 서버 app_user_directory(나·차단 제외)
// · SharedRouting(깃발) 와 같은 답인지. 발신 수는 MockEngine 녹음으로 잰다.
package com.yehsung.aingcheck.desktop.pages.poke

import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.desktop.pages.shared.SharedRouter
import com.yehsung.aingcheck.desktop.pages.ultra.DIRECTORY_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.FakeServer
import com.yehsung.aingcheck.desktop.pages.ultra.FakeSessionHost
import com.yehsung.aingcheck.desktop.pages.ultra.ME
import com.yehsung.aingcheck.desktop.pages.ultra.POKE_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.Reply
import com.yehsung.aingcheck.desktop.pages.ultra.TestClock
import com.yehsung.aingcheck.desktop.pages.ultra.ULTRA_POKE_PATH
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeSender
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraWalletTrigger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val A = "00000000-0000-4000-8000-00000000000a" // 근무중
private const val B = "00000000-0000-4000-8000-00000000000b" // 자리비움
private const val C = "00000000-0000-4000-8000-00000000000c" // 방금 차단(서버 재조회 전)
private const val D = "00000000-0000-4000-8000-00000000000d" // 근무중

/** 합성 명부. 일부러 서버가 빼야 할 '나'를 섞는다(서버 규칙이 새도 화면이 막는지). */
private val DIRECTORY = """
    [
      {"user_id":"$B","display_name":"나비","is_working":false},
      {"user_id":"${ME.uppercase()}","display_name":"나","is_working":true},
      {"user_id":"$D","display_name":"다람","is_working":true,"status_message":"집중해서 일하는 중"},
      {"user_id":"$C","display_name":"가람","is_working":true},
      {"user_id":"$A","display_name":"라온","is_working":true}
    ]
""".trimIndent()

@OptIn(ExperimentalCoroutinesApi::class)
class PokeListPageTest {
    private class Rig(scope: TestScope, config: DesktopAppConfig = DesktopAppConfig(poke = true, ultra = true)) {
        val server = FakeServer(scope).on("POST", DIRECTORY_PATH, Reply.Json(DIRECTORY))
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        var working = true
        var hidden = setOf(C)
        var unreadMessages = emptySet<String>()
        var walletSyncs = 0
        val sender = DesktopPokeSender(host, scope, clock::now, localSessionOpen = { working }, wallet = UltraWalletTrigger { walletSyncs += 1 })
        val model = PokeListModel(
            PokeListDeps(
                host = host, config = config, sender = if (config.poke) sender else null, wallet = null, focus = null, scope = scope,
                clock = clock::now, localSessionOpen = { working }, hiddenBlockedPeerIDs = { hidden }, unreadMessagePeerIDs = { unreadMessages },
            ),
        )

        fun entry(id: String): PokeDirectoryEntry = model.rows().first { it.userID == id }
    }

    private fun pTo(body: String): String = Json.parseToJsonElement(body).jsonObject.getValue("p_to").jsonPrimitive.content

    @Test
    fun `나 자신·차단 상대는 목록에 없고 보내기 0건`() = runTest {
        val r = Rig(this)
        r.model.onOpen()
        advanceUntilIdle()
        assertEquals(1, r.server.count("POST", DIRECTORY_PATH))
        val ids = r.model.rows().map { it.userID }
        assertTrue(ME.uppercase() !in ids && ME !in ids, "나 자신이 목록에 섰다: $ids")
        assertTrue(C !in ids, "차단 숨김 상대가 목록에 섰다: $ids")
        assertNull(r.model.poke(ME.uppercase()))
        assertNull(r.model.poke(C))
        assertNull(r.model.ultra(C))
        advanceUntilIdle()
        assertEquals(0, r.server.count("POST", POKE_PATH) + r.server.count("POST", ULTRA_POKE_PATH))
        // 숨김이 풀리면(차단 실패) 다시 묻지 않아도 돌아온다.
        r.hidden = emptySet()
        assertTrue(C in r.model.rows().map { it.userID })
    }

    @Test
    fun `보내기 1회 = poke_user 1건 · 날아가는 중·쿨타임 동안 0건 · 60초 뒤 다시 가능`() = runTest {
        val gate = CompletableDeferred<Unit>()
        val r = Rig(this)
        r.server.on("POST", POKE_PATH, Reply.Hold(gate, Reply.Json("""{"status":"ok"}""")), Reply.Json("""{"status":"ok"}"""))
        r.model.onOpen()
        advanceUntilIdle()
        assertEquals(PokeButtonState.READY, r.model.buttonState(r.entry(A), r.clock.now()))
        assertTrue(r.model.poke(A) != null)
        runCurrent()
        assertNull(r.model.poke(A), "같은 대상 날아가는 중 두 번째 누름이 요청을 냈다")
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, r.server.count("POST", POKE_PATH), "poke_user 요청 수")
        assertEquals(A, pTo(r.server.bodies("POST", POKE_PATH).single()))
        // 쿨타임(서버 강제 60초를 클라가 미러링) — 단추는 흐리고 눌러도 0건.
        assertEquals(PokeButtonState.COOLDOWN, r.model.buttonState(r.entry(A), r.clock.now()))
        assertNull(r.model.poke(A))
        r.clock.advance(59.5)
        assertEquals(PokeButtonState.COOLDOWN, r.model.buttonState(r.entry(A), r.clock.now()), "올림 정수 초 — 0.5초 남아도 쿨타임")
        r.clock.advance(0.5)
        assertEquals(PokeButtonState.READY, r.model.buttonState(r.entry(A), r.clock.now()))
        r.model.poke(A)
        advanceUntilIdle()
        assertEquals(2, r.server.count("POST", POKE_PATH))
        // 다른 대상은 쿨타임과 무관.
        assertEquals(PokeButtonState.READY, r.model.buttonState(r.entry(D), r.clock.now()))
    }

    @Test
    fun `내 비근무 · 대상 자리비움 — 단추가 아니고 0건 · 맥 순서(쿨타임 먼저)`() = runTest {
        val r = Rig(this)
        r.model.onOpen()
        advanceUntilIdle()
        assertEquals(PokeButtonState.TARGET_AWAY, r.model.buttonState(r.entry(B), r.clock.now()))
        assertNull(r.model.poke(B))
        r.working = false
        assertEquals(PokeButtonState.MYSELF_OFF_WORK, r.model.buttonState(r.entry(A), r.clock.now()))
        assertEquals(PokeButtonState.MYSELF_OFF_WORK, r.model.buttonState(r.entry(B), r.clock.now()), "내 비근무가 대상 자리비움보다 앞선다")
        assertNull(r.model.poke(A))
        advanceUntilIdle()
        assertEquals(0, r.server.count("POST", POKE_PATH))
        assertEquals(PokeButtonState.COOLDOWN, PokeListRules.buttonState(remainingCooldown = 1, isMyselfWorking = false, targetWorking = false))
        assertEquals("잠시 후 다시 찌를 수 있어요", PokeButtonState.COOLDOWN.tooltip)
        assertEquals("내가 근무 중일 때만 콕 찌를 수 있어요", PokeButtonState.MYSELF_OFF_WORK.tooltip)
        assertEquals("자리비움 상태에는 찌를 수 없어요", PokeButtonState.TARGET_AWAY.tooltip)
    }

    @Test
    fun `정렬 — 안 읽음 → 근무중 → 이름(core sortedForPokeDisplay)`() = runTest {
        val r = Rig(this)
        r.model.onOpen()
        advanceUntilIdle()
        assertEquals(listOf("다람", "라온", "나비"), r.model.rows().map { it.name })
        r.unreadMessages = setOf(B)
        assertEquals(listOf("나비", "다람", "라온"), r.model.rows().map { it.name })
        assertEquals(PokeRowUnreadMark.MESSAGES, PokeRowUnreadMark.of(B, setOf(B), setOf(B)))
        assertEquals(PokeRowUnreadMark.POKES_ONLY, PokeRowUnreadMark.of(B, emptySet(), setOf(B)))
        // 디렉터리 원본 순서와 무관(같은 입력 다른 순서 → 같은 답).
        val shuffled = r.model.directory.entries.value.reversed()
        assertEquals(
            r.model.rows().map { it.userID },
            PokeListRules.visibleEntries(shuffled, ME, setOf(C), setOf(B), emptySet(), NaturalKoNameCollation).map { it.userID },
        )
    }

    @Test
    fun `울트라 콕 — ultra 켜짐이면 ultra_poke_user 1건 · 꺼짐이면 0건(일반은 산다)`() = runTest {
        val on = Rig(this)
        on.server.on("POST", ULTRA_POKE_PATH, Reply.Json("""{"status":"ok","ultra_balance":1}"""))
        on.model.onOpen()
        advanceUntilIdle()
        on.model.ultra(A)
        advanceUntilIdle()
        assertEquals(1, on.server.count("POST", ULTRA_POKE_PATH))
        assertEquals(0, on.server.count("POST", POKE_PATH))
        assertEquals(1, on.walletSyncs, "울트라 발사 성공 → 지갑 MissionCandidate")

        val off = Rig(this, DesktopAppConfig(poke = true, ultra = false))
        off.server.on("POST", POKE_PATH, Reply.Json("""{"status":"ok"}"""))
        off.model.onOpen()
        advanceUntilIdle()
        assertNull(off.model.ultra(A))
        off.model.poke(A)
        advanceUntilIdle()
        assertEquals(0, off.server.count("POST", ULTRA_POKE_PATH))
        assertEquals(1, off.server.count("POST", POKE_PATH))
        assertEquals("콕 찌르기", UltraBalanceText.rowTooltip(3, unlimited = false, ultraPoke = false))

        val pokeOff = Rig(this, DesktopAppConfig(poke = false, ultra = true))
        pokeOff.model.onOpen()
        advanceUntilIdle()
        assertNull(pokeOff.model.poke(A))
        assertNull(pokeOff.model.ultra(A))
        advanceUntilIdle()
        assertEquals(0, pokeOff.server.count("POST", POKE_PATH) + pokeOff.server.count("POST", ULTRA_POKE_PATH))
    }

    @Test
    fun `깃발 판정 — visibleRoutes 네 조합이 SharedRouter 와 같은 답`() {
        for (poke in listOf(false, true)) for (ultra in listOf(false, true)) {
            val config = DesktopAppConfig(poke = poke, ultra = ultra)
            val routes = SocialPageFlags.visibleRoutes(config)
            assertEquals(poke, FlyoutRoute.PokeList in routes, "poke=$poke ultra=$ultra")
            assertEquals(ultra, FlyoutRoute.Ultra in routes, "poke=$poke ultra=$ultra")
            for (route in listOf(FlyoutRoute.PokeList, FlyoutRoute.Ultra)) {
                assertEquals(SharedRouter.isEnabled(route, config), route in routes, "$route poke=$poke ultra=$ultra — 라우터와 갈렸다")
            }
            val s = SocialPageFlags.surfaces(config)
            assertEquals(poke && ultra, s.ultraPoke, "울트라 콕은 poke·ultra 둘 다")
            assertEquals(ultra, s.ultraPurchase)
            assertEquals(ultra, s.walletBalance)
            assertEquals(poke, s.focusControl, "집중 단추는 맥처럼 콕 목록 제목 행에만")
        }
        assertEquals(emptySet(), SocialPageFlags.visibleRoutes(DesktopAppConfig()), "기본값(전부 꺼짐)은 두 라우트 다 숨김")
    }

    @Test
    fun `안내줄 — 연결 끊김 › 메시지 › 찌르기 › 내 비근무 › 집중 단계 · 빈 목록 문구`() {
        assertEquals(PokeNoticeLine(PokeListRules.DISCONNECTED, true), PokeListRules.noticeLine(true, "m", "n", false, FocusStage.ALWAYS))
        assertEquals(PokeNoticeLine("m", true), PokeListRules.noticeLine(false, "m", "n", false, FocusStage.ALWAYS))
        assertEquals(PokeNoticeLine("n", true), PokeListRules.noticeLine(false, "", "n", false, FocusStage.ALWAYS))
        assertEquals(PokeNoticeLine(PokeListRules.POKE_OFF_WORK, false), PokeListRules.noticeLine(false, null, null, false, FocusStage.ALWAYS))
        assertEquals(
            PokeNoticeLine("집중 모드 1단 — 3시간 동안 콕찌르기를 받지 않아요", false),
            PokeListRules.noticeLine(false, null, null, true, FocusStage.TIMED),
        )
        assertNull(PokeListRules.noticeLine(false, null, null, true, FocusStage.OFF))
        assertEquals("아직 다른 사용자가 없어요", PokeListRules.emptyText(true, "불러오는 중…"))
        assertEquals("불러오는 중…", PokeListRules.emptyText(false, "불러오는 중…"))
        assertEquals("99+", UltraBalanceText.badge(100))
        assertEquals("3초 꾹", UltraBalanceText.hint(100))
        assertEquals("상점에서 사기", UltraBalanceText.hint(0))
        assertEquals("3초 꾹 = 울트라", UltraBalanceText.hint(null))
    }
}
