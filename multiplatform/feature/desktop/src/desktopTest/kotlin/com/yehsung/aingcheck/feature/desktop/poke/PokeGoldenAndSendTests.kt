// W2-g2 골든·발신 시험 — contract/golden/desktop-poke/{fresh,send-notice,requests}.json(Swift GoldenExportDesktopPoke 가 낸다)
// · Swift WorkTimerStorePoke.swift 104-238(P1 P2 P3).
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeSendOutcome
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.poke.net.sendPoke
import com.yehsung.aingcheck.feature.desktop.poke.net.sendUltraPoke
import com.yehsung.aingcheck.feature.desktop.poke.net.takePokes
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.isJsonNull
import com.yehsung.aingcheck.testkit.golden.long
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.mock.MockRouter
import com.yehsung.aingcheck.testkit.mock.StubResponse
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun JsonObject.opt(key: String): String? = this[key]?.takeUnless { it.isJsonNull() }?.jsonPrimitive?.content
private fun JsonElement.obj(): JsonObject = jsonObject

class DesktopPokeGoldenTest {
    private val service = pokeService(MockRouter())

    @Test
    fun freshMatchesSwift() {
        val golden = Golden.load("desktop-poke/fresh")
        assertTrue(golden.cases.size >= 3)
        for (case in golden.cases) {
            val id = case.string("id")
            val now = SwiftDate(case.long("now").toDouble())
            val rows = service.decode(ListSerializer(TakenPokeRow.serializer()), case.string("rowsJSON").encodeToByteArray())
            val pokes = DesktopPokeRules.freshReceivedPokes(rows, now).map {
                listOf(it.id, it.fromName, it.createdAt.timeIntervalSince1970.toLong().toString(), it.kind.rawValue, it.fromCharacterID)
            }
            val expectedPokes = case.array("pokes").map { e ->
                val o = e.obj()
                listOf(o.string("id"), o.string("fromName"), o.long("createdAt").toString(), o.string("kind"), o.opt("fromCharacterID"))
            }
            assertEquals(expectedPokes, pokes, golden.failure(id, "pokes"))
            val messages = DesktopPokeRules.freshReceivedMessages(rows, now, RulesWireTextRules).map {
                listOf(it.id, it.fromName, it.body, it.createdAt.timeIntervalSince1970.toLong().toString(), it.fromUserID, it.fromAvatarURL)
            }
            val expectedMessages = case.array("messages").map { e ->
                val o = e.obj()
                listOf(o.string("id"), o.string("fromName"), o.string("body"), o.long("createdAt").toString(), o.opt("fromUserID"), o.opt("fromAvatarURL"))
            }
            assertEquals(expectedMessages, messages, golden.failure(id, "messages"))
        }
    }

    @Test
    fun sendNoticeMatchesSwift() {
        val golden = Golden.load("desktop-poke/send-notice")
        for (r in golden.case("ultra-sent").array("rows")) {
            val o = r.obj()
            val balance = o["balance"]?.takeUnless { it.isJsonNull() }?.jsonPrimitive?.long
            assertEquals(o.string("notice"), DesktopPokeRules.ultraSentNotice(balance), golden.failure("ultra-sent", "balance=$balance"))
        }
        val c = golden.case("constants")
        assertEquals(c.string("ultraEmptyNotice"), DesktopPokeRules.ULTRA_EMPTY_NOTICE)
        assertEquals(c.string("targetFocusedNotice"), DesktopPokeRules.TARGET_FOCUSED_NOTICE)
        assertEquals(c.string("targetOnPhoneNotice"), DesktopPokeRules.TARGET_ON_PHONE_NOTICE)
        assertEquals(c.long("pokePollIntervalSeconds").toDouble(), DesktopPokeRules.POLL_INTERVAL_SECONDS)
        assertEquals(c.long("pokePollIntervalSecondsWhileSubscribed").toDouble(), DesktopPokeRules.POLL_INTERVAL_SECONDS_WHILE_SUBSCRIBED)
        assertEquals(c.long("pokeDisplayFreshnessSeconds").toDouble(), DesktopPokeRules.POKE_DISPLAY_FRESHNESS_SECONDS)
        assertEquals(c.long("ultraDisplayFreshnessSeconds").toDouble(), DesktopPokeRules.ULTRA_DISPLAY_FRESHNESS_SECONDS)
        assertEquals(c.long("pokeCooldownSeconds").toDouble(), DesktopPokeRules.COOLDOWN_SECONDS)
        assertEquals(c.long("adoptedPokeConsumerInputWindowSeconds").toDouble(), DesktopPokeRules.ADOPTED_CONSUMER_INPUT_WINDOW_SECONDS)
        assertEquals(c.long("messageQueueLimit").toInt(), DesktopPokeRules.MESSAGE_QUEUE_LIMIT)
        assertEquals(c.long("messageDisplayFreshnessSeconds").toDouble(), DesktopPokeRules.MESSAGE_DISPLAY_FRESHNESS_SECONDS)
        assertEquals(c["pollingKeepsRunningAlongsideRealtime"]!!.jsonPrimitive.content.toBoolean(), DesktopPokeRules.POLLING_KEEPS_RUNNING_ALONGSIDE_REALTIME)
        for (r in golden.case("outcomes").array("rows")) {
            val o = r.obj()
            val response = service.decode(PokeSendResponse.serializer(), o.string("response").encodeToByteArray())
            val outcome = when (val x = PokeSendOutcome.of(response)) {
                PokeSendOutcome.Ok -> "ok"
                is PokeSendOutcome.Cooldown -> "cooldown:${x.retryAfterSeconds}"
                PokeSendOutcome.NotWorking -> "notWorking"
                PokeSendOutcome.TargetNotWorking -> "targetNotWorking"
                is PokeSendOutcome.UltraUsedToday -> "ultraUsedToday:${x.resetAfterSeconds}"
                PokeSendOutcome.TargetFocused -> "targetFocused"
                PokeSendOutcome.TargetOnPhone -> "targetOnPhone"
                PokeSendOutcome.Invalid -> "invalid"
            }
            assertEquals(o.string("outcome"), outcome, golden.failure("outcomes", o.string("response")))
            assertEquals(o.opt("ultraBalanceForDisplay"), response.ultraBalanceForDisplay?.toString(), golden.failure("outcomes", o.string("response")))
        }
    }

    @Test
    fun requestsMatchSwiftBytes() = runBlocking {
        val golden = Golden.load("desktop-poke/requests")
        val rpcOf = mapOf("poke-user" to "poke_user", "ultra-poke-user" to "ultra_poke_user", "take-pokes" to "take_pokes",
            "take-pokes-fallback-then-new-shape" to "take_pokes")
        assertEquals(rpcOf.keys, golden.cases.map { it.string("id") }.toSet())
        for (case in golden.cases) {
            val id = case.string("id")
            val script = case.array("script").map { e -> e.obj().let { StubResponse.Json(it.string("body"), it.long("status").toInt()) } }
            val router = MockRouter().rpc(rpcOf.getValue(id), *script.toTypedArray())
            val s = pokeService(router)
            val result = when (id) {
                "poke-user" -> s.sendPoke("token", "user-1").status
                "ultra-poke-user" -> s.sendUltraPoke("token", "user-2").status
                "take-pokes" -> "rows:${s.takePokes("token").size}"
                else -> "rows:${s.takePokes("token").size},${s.takePokes("token").size}"
            }
            assertEquals(case.string("result"), result, golden.failure(id, "result"))
            val expected = case.array("requests").map { e -> e.obj().let { listOf(it.string("method"), it.string("path"), it.string("body")) } }
            assertEquals(expected, router.requests.map { listOf(it.method, it.path, it.bodyText) }, golden.failure(id, "requests"))
            router.assertAllRouted()
        }
    }
}

class PokeSendEffectsTest {
    private fun r(json: String) = pokeService(MockRouter()).decode(PokeSendResponse.serializer(), json.encodeToByteArray())

    /** P2 표. */
    @Test
    fun outcomeTable() {
        val notWorkingTarget = PokeSendEffects.of(false, r("""{"status":"target_not_working"}"""), null)
        assertTrue(notWorkingTarget.reloadDirectory, "target_not_working → 디렉터리 다시 읽기")
        val onPhone = PokeSendEffects.of(false, r("""{"status":"target_on_phone"}"""), null)
        assertEquals(false, onPhone.reloadDirectory, "target_on_phone → 다시 읽지 않는다")
        assertEquals(PokeNoticeChange.Set(DesktopPokeRules.TARGET_ON_PHONE_NOTICE), onPhone.notice)
        for (status in listOf("target_focused", "target_on_phone", "target_not_working", "not_working", "invalid")) {
            assertNull(PokeSendEffects.of(true, r("""{"status":"$status","ultra_balance":7}"""), 3).ultraBalance, "울트라 $status 는 잔량을 건드리지 않는다")
        }
        assertEquals(0L, PokeSendEffects.of(true, r("""{"status":"ultra_used_today"}"""), 3).ultraBalance, "ultra_used_today · 잔량 없음 → 0")
        assertEquals(2L, PokeSendEffects.of(true, r("""{"status":"ultra_used_today","ultra_balance":2}"""), 3).ultraBalance)
        val ultraOkNoKey = PokeSendEffects.of(true, r("""{"status":"ok"}"""), 4)
        assertNull(ultraOkNoKey.ultraBalance, "ok · 서버 잔량 nil → 덮지 않는다")
        assertEquals(PokeNoticeChange.Set("울트라 발사! 남은 울트라 4개"), ultraOkNoKey.notice, "안내는 직전 잔량")
        assertEquals(PokeNoticeChange.Set("울트라 찌르기 발사!"), PokeSendEffects.of(true, r("""{"status":"ok"}"""), null).notice, "P3 모르면 지어내지 않는다")
        val ultraOk = PokeSendEffects.of(true, r("""{"status":"ok","ultra_balance":1}"""), 4)
        assertEquals(1L, ultraOk.ultraBalance)
        // P3 ★ 안내 잔량은 서버값이 먼저(Swift `ultraSentNotice(balance: response.ultraBalanceForDisplay ?? ultraBalance)`) — 직전 4 가 아니라 1.
        assertEquals(PokeNoticeChange.Set("울트라 발사! 남은 울트라 1개"), ultraOk.notice, "P3 서버 잔량 1 이 직전 잔량 4 를 이긴다")
        assertEquals(60.0, ultraOk.cooldownSeconds, "울트라 ok 도 쿨타임 60 미러")
        assertTrue(ultraOk.walletMissionCandidate && ultraOk.refreshConversation)
        val normalOk = PokeSendEffects.of(false, r("""{"status":"ok"}"""), null)
        assertEquals(PokeNoticeChange.Set(null), normalOk.notice)
        assertEquals(false, normalOk.walletMissionCandidate)
        assertEquals(PokeNoticeChange.Keep, PokeSendEffects.of(false, r("""{"status":"cooldown","retry_after_seconds":42}"""), null).notice)
        assertEquals(42.0, PokeSendEffects.of(false, r("""{"status":"cooldown","retry_after_seconds":42}"""), null).cooldownSeconds)
        assertEquals(PokeNoticeChange.Set(DesktopPokeRules.ULTRA_COOLDOWN_NOTICE), PokeSendEffects.of(true, r("""{"status":"cooldown"}"""), null).notice)
    }

    /** P1: 선게이트는 세션 + 로컬 세션 열림. 울트라는 로컬 잔량으로 막지 않는다. */
    @Test
    fun senderPreGateAndUltraOkFlow() = runBlocking {
        val router = MockRouter().rpc("ultra_poke_user", StubResponse.Json("""{"status":"ok","ultra_balance":0}"""))
        val host = FakeSessionHost(pokeService(router))
        val wallet = mutableListOf<UltraSyncReason>()
        val balances = mutableListOf<Long>()
        val hooks = object : PokeSendHooks {
            override fun applyUltraBalance(balance: Long) { balances += balance }
            // 직전 잔량(5)을 서버값(0)과 다르게 둔다 — 안내가 어느 쪽에서 왔는지 갈린다(P3 서버 먼저).
            override val currentUltraBalance: Long? get() = 5
        }
        var open = false
        val sender = DesktopPokeSender(host, this, { T0 }, { open }, { wallet += it }, hooks)
        assertNull(sender.sendUltraPoke("peer"))
        assertEquals(DesktopPokeRules.NOT_WORKING_NOTICE, sender.notice.value)
        assertEquals(0, router.requests.size, "비근무면 요청을 내지 않는다")
        open = true
        sender.sendUltraPoke("peer")!!.join()
        assertEquals("울트라 발사! 이제 0개예요", sender.notice.value, "잔량 0 이어도 요청은 나갔다(서버 판정)")
        assertEquals(listOf(UltraSyncReason.MissionCandidate), wallet)
        assertEquals(listOf(0L), balances)
        assertEquals(60, sender.cooldownRemaining("peer", T0))
        sender.pruneExpiredCooldowns(T0.addingTimeInterval(61.0))
        assertEquals(0, sender.cooldownRemaining("peer", T0))
        host.current = null
        assertNull(sender.sendPoke("peer"), "세션 없음 → 아무것도")
    }

    @Test
    fun networkFailureNotice() = runBlocking {
        val router = MockRouter().rpc("poke_user", StubResponse.TransportFailure())
        val sender = DesktopPokeSender(FakeSessionHost(pokeService(router)), this, { T0 }, { true }, { })
        sender.sendPoke("peer")!!.join()
        assertEquals(DesktopPokeRules.NETWORK_NOTICE, sender.notice.value)
        assertEquals(1, DesktopPokeRules.cooldownRemaining(T0.addingTimeInterval(0.2), T0), "올림")
    }

    /** 바깥에 닿은 일을 한 줄로 — 세대 가드 시험이 '아무것도 안 닿음'과 '다 닿음'을 같은 눈금으로 잰다. */
    private class Touches : PokeSendHooks {
        val balances = mutableListOf<Long>()
        val refreshed = mutableListOf<String>()
        var reloads = 0
        val wallet = mutableListOf<UltraSyncReason>()
        override fun applyUltraBalance(balance: Long) { balances += balance }
        override fun refreshConversationAfterPokeSent(peerUserID: String) { refreshed += peerUserID }
        override fun reloadDirectory() { reloads++ }
        override val currentUltraBalance: Long? get() = 5
        fun line(sender: DesktopPokeSender, vararg peers: String): String =
            "notice=${sender.notice.value} cooldown=${peers.map { sender.cooldownRemaining(it, T0) }} balances=$balances " +
                "wallet=$wallet refreshed=$refreshed reloads=$reloads"
    }

    /**
     * 발신 세대 가드 · 성공 경로(Swift sendPoke·sendUltraPoke `guard generation == sessionGeneration else { return }` — 응답 뒤).
     * 응답 도중 로그아웃·재로그인이면 옛 응답은 새 계정의 안내·쿨타임·울트라 잔량·지갑 sync·대화·디렉터리 어디에도 닿지 않는다.
     */
    @Test
    fun successResponseAfterRelogInTouchesNothing() = runBlocking {
        val router = MockRouter()
            .rpc("ultra_poke_user", StubResponse.Json("""{"status":"ok","ultra_balance":2}"""), StubResponse.Json("""{"status":"ok","ultra_balance":2}"""))
            .rpc("poke_user", StubResponse.Json("""{"status":"target_not_working"}"""), StubResponse.Json("""{"status":"target_not_working"}"""))
        val host = FakeSessionHost(pokeService(router))
        val touches = Touches()
        val sender = DesktopPokeSender(host, this, { T0 }, { true }, { touches.wallet += it }, touches)
        host.onOperationEnd = { host.generation++ }
        sender.sendUltraPoke("peer-u")!!.join()
        sender.sendPoke("peer-n")!!.join()
        assertEquals(2, router.requests.size, "요청은 나갔다 — 막힌 건 응답의 착지")
        assertEquals("notice=null cooldown=[0, 0] balances=[] wallet=[] refreshed=[] reloads=0", touches.line(sender, "peer-u", "peer-n"),
            "세대가 바뀐 뒤 도착한 성공 응답은 아무 데도 닿지 않는다")
        // 대조: 같은 응답, 세대 그대로 → 다 닿는다(위 줄이 '원래 아무 효과 없는 응답' 탓이 아님을 보인다).
        host.onOperationEnd = null
        sender.sendUltraPoke("peer-u")!!.join()
        sender.sendPoke("peer-n")!!.join()
        assertEquals(
            "notice=${DesktopPokeRules.TARGET_NOT_WORKING_NOTICE} cooldown=[60, 0] balances=[2] wallet=[MissionCandidate] refreshed=[peer-u] reloads=1",
            touches.line(sender, "peer-u", "peer-n"),
        )
        router.assertAllRouted()
    }

    /** 발신 세대 가드 · 실패 경로(Swift `catch { … guard generation == sessionGeneration else { return } }`) — 새 계정에 옛 네트워크 안내 없음. */
    @Test
    fun failureAfterRelogInLeavesNoNotice() = runBlocking {
        for (ultra in listOf(false, true)) {
            val rpc = if (ultra) "ultra_poke_user" else "poke_user"
            val router = MockRouter().rpc(rpc, StubResponse.TransportFailure(), StubResponse.TransportFailure())
            val host = FakeSessionHost(pokeService(router)).apply { onOperationEnd = { generation++ } }
            val sender = DesktopPokeSender(host, this, { T0 }, { true }, { })
            val send = { if (ultra) sender.sendUltraPoke("peer") else sender.sendPoke("peer") }
            send()!!.join()
            assertNull(sender.notice.value, "ultra=$ultra: 세대가 바뀐 뒤 실패는 안내를 띄우지 않는다")
            host.onOperationEnd = null
            send()!!.join()
            assertEquals(DesktopPokeRules.NETWORK_NOTICE, sender.notice.value, "ultra=$ultra 대조: 세대 그대로면 네트워크 안내")
        }
    }
}

class PokeNoticeSourceContractTest {
    /** 주석을 걷어 낸 Swift 원본(따옴표 밖 `//` 이후를 지운다 — 주석 속 옛 문구가 계약을 대신하지 못하게). */
    private val swift: String = RepoFiles.readText("Sources/check/WorkTimerStorePoke.swift").lines().joinToString("\n") { line ->
        var quotes = 0
        var cut = line.length
        var i = 0
        while (i < line.length - 1) {
            if (line[i] == '"') quotes++
            if (line[i] == '/' && line[i + 1] == '/' && quotes % 2 == 0) { cut = i; break }
            i++
        }
        line.substring(0, cut)
    }

    /** sendPoke·sendUltraPoke 의 갈래 안 문구(골든으로 못 재는 인라인 글자)가 Swift 원본에 그대로 있다. */
    @Test
    fun inlineNoticesExistInSwiftSource() {
        for (notice in listOf(
            DesktopPokeRules.NOT_WORKING_NOTICE, DesktopPokeRules.TARGET_NOT_WORKING_NOTICE, DesktopPokeRules.INVALID_NOTICE,
            DesktopPokeRules.NETWORK_NOTICE, DesktopPokeRules.ULTRA_COOLDOWN_NOTICE,
        )) {
            assertTrue("pokeNotice = \"$notice\"" in swift, "Swift 원본에 pokeNotice = \"$notice\" 가 없다")
        }
        assertTrue("pokeNotice = Self.ultraEmptyNotice" in swift && "pokeNotice = Self.targetOnPhoneNotice" in swift)
    }
}
