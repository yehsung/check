// 원본: Tests/CheckMobileKitTests/MessagesStoreTests.swift · MessagesPokeLogStoreTests.swift · MessagesBlockReportTests.swift @ 1b8260d
// G §2-3 W2-b ① 녹음기 위반 [] · ② 메시지 규칙 ①~⑤(MessagesStore.swift:16-25 머리) — 시험마다 끝에 assertClean().
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 메시지 서버 흉내(메시지 행 · 찌르기 행 · 요약 · 읽음 · 보내기 · 사람 찾기 · 차단). 읽음 표시는 서버처럼 그 사람의 받은 행을 경계까지 읽음으로 바꾼다.
 * 함수가 없는 서버는 [missing] 에 이름을 넣는다.
 */
class MessagesServer {
    class Row(
        val id: String, val peer: String, val name: String, val body: String?, val at: Long, val mine: Boolean,
        val readByPeer: Boolean?, var unread: Boolean?, val kind: String,
    )

    val base: Long = 1_789_621_500 - 600   // 데모 시각 10분 전(epoch 초)
    val rows = mutableListOf<Row>()
    val messages: List<Row> get() = rows.filter { it.kind == "message" }
    val missing = mutableSetOf<String>()
    var summary = """{"status":"ok","total":0,"peers":[]}"""
    var sendReply: Reply = Reply.Json("""{"status":"ok"}""")
    var directory = "[]"
    var blockReply: Reply = Reply.Json("{}")
    var unblockReply: Reply = Reply.Json("{}")
    var listBlocksReply: Reply = Reply.Json("[]")
    var reportReply: Reply = Reply.Json("{}")
    var historyGate: CompletableDeferred<Unit>? = null

    /** 요약 조회를 붙잡는 문(늦은 옛 요약 재현). 요청이 **들어온 순간**의 [summary] 를 싣고 기다린다. */
    var summaryGate: CompletableDeferred<Unit>? = null

    fun received(id: String, peer: String, at: Long, unread: Boolean? = true, name: String = "상대", body: String = "안녕") {
        rows += Row(id, peer, name, body, at, mine = false, readByPeer = null, unread = unread, kind = "message")
    }

    fun sent(id: String, peer: String, at: Long, readByPeer: Boolean? = false, body: String = "보냄") {
        rows += Row(id, peer, "상대", body, at, mine = true, readByPeer = readByPeer, unread = null, kind = "message")
    }

    fun poke(id: String, peer: String, at: Long, mine: Boolean = false, unread: Boolean? = true, kind: String = "poke", name: String = "상대") {
        rows += Row(id, peer, name, null, at, mine, readByPeer = null, unread = if (mine) null else unread, kind = kind)
    }

    private fun json(row: Row, withKind: Boolean): String {
        fun q(v: String?) = v?.let { "\"$it\"" } ?: "null"
        fun f(v: Boolean?) = v?.toString() ?: "null"
        val from = if (row.mine) StoreHarness.ME else row.peer
        val to = if (row.mine) row.peer else StoreHarness.ME
        return """{"id":"${row.id}","from_user":${q(from)},"to_user":${q(to)},"body":${q(row.body)},"created_at":null,""" +
            """"is_mine":${row.mine},"peer_user_id":"${row.peer}","peer_display_name":"${row.name}","peer_avatar_url":null,""" +
            """"created_epoch":${base + row.at},"read_by_peer":${f(row.readByPeer)},"unread":${f(row.unread)}""" +
            (if (withKind) ""","kind":"${row.kind}"}""" else "}")
    }

    /** 서버 순서(created_epoch · id 오름차순)로 섞어 준다. */
    private fun withPokes(): String = "[" + rows.sortedWith(compareBy({ it.at }, { it.id })).joinToString(",") { json(it, true) } + "]"

    private fun withoutKind(): String = "[" + messages.sortedWith(compareBy({ it.at }, { it.id })).joinToString(",") { json(it, false) } + "]"

    /** 그 사람의 받은 행(종류 하나)을 경계까지 읽음으로(서버 mark_* 의 효과). */
    private fun markRead(peer: String, through: String?, pokes: Boolean) {
        through ?: return
        val own = rows.filter { it.peer == peer && !it.mine && (it.kind != "message") == pokes }.sortedWith(compareBy({ it.at }, { it.id }))
        val index = own.indexOfFirst { it.id == through }
        if (index < 0) return
        for (row in own.take(index + 1)) row.unread = false
    }

    private fun field(r: RecordedRequest, key: String): String? =
        (SwiftJson.parse(r.bodyText) as? JsonObject)?.get(key)?.let { if (it is kotlinx.serialization.json.JsonNull) null else it.jsonPrimitive.content }

    fun route(r: RecordedRequest): Reply? {
        val rpc = r.rpcName ?: return null
        if (rpc in missing) return Reply.missingFunction
        return when (rpc) {
            "message_history_with_pokes" -> historyGate?.let { Reply.Gate(it, Reply.Json(withPokes())) } ?: Reply.Json(withPokes())
            "message_history_with_reads", "message_history" -> Reply.Json(withoutKind())
            "message_unread_summary" -> summaryGate?.let { Reply.Gate(it, Reply.Json(summary)) } ?: Reply.Json(summary)
            "mark_conversation_read" -> {
                val peer = field(r, "p_peer")!!
                markRead(peer, field(r, "p_through_message"), pokes = false)
                markRead(peer, field(r, "p_through_poke"), pokes = true)
                Reply.Json("""{"status":"ok","advanced":true,"unread":0,"poke_advanced":true,"poke_unread":0}""")
            }
            "mark_messages_read" -> {
                markRead(field(r, "p_peer")!!, field(r, "p_through"), pokes = false)
                Reply.Json("""{"status":"ok","advanced":true,"unread":0}""")
            }
            "send_message" -> sendReply
            "app_user_directory" -> Reply.Json(directory)
            "block_user" -> blockReply
            "unblock_user" -> unblockReply
            "list_blocks" -> listBlocksReply
            "report_content" -> reportReply
            else -> null
        }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesStoreTest {
    private val peerA = "peer-a"
    private val peerB = "peer-b"

    private suspend fun TestScope.make(setup: (MessagesServer) -> Unit = {}): Triple<StoreHarness, MessagesServer, MessagesStore> {
        val server = MessagesServer().also(setup)
        val h = StoreHarness(this) { server.route(it) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        return Triple(h, server, store)
    }

    private fun bodies(h: StoreHarness, rpc: String): List<String> = h.storeRequests.filter { it.rpcName == rpc }.map { it.bodyText }

    // ---------------------------------------------------------------- ① take_pokes 0 · 조회로만 갚는다

    @Test
    fun activityIsPaidByQueriesNeverTakePokes() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0) }
        store.appDidBecomeActive()
        advanceUntilIdle()
        // 목록이 안 보이면 요약만 — 이력은 낡음으로 적는다(④).
        assertEquals(listOf("rpc/message_unread_summary"), h.paths())
        assertTrue(store.isHistoryStale)
        store.listDidAppear()
        advanceUntilIdle()
        assertEquals(1, h.count("message_history_with_pokes"), "목록이 서면 스로틀과 무관하게 곧바로 이력")
        assertFalse(store.isHistoryStale)
        // 실시간 신호 · 푸시 · 화면 표시 — 모두 조회(요약 · 이력)로만 갚는다.
        store.realtimeMessageActivity()
        store.realtimeMessageRead()
        store.didReceiveMessagePush(peerA)
        advanceUntilIdle()
        server.received("a2", peerA, 5)
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertTrue(h.storeRequests.all { it.rpcName != "take_pokes" }, "take_pokes 를 불렀다")
        assertTrue(h.storeRequests.all { it.method == "POST" && it.rpcName != null }, "RPC 밖 요청: ${h.paths()}")
        h.assertClean()
    }

    // ---------------------------------------------------------------- ② 읽음은 서버 판정 · active + 그 대화일 때만

    @Test
    fun readMarkingOnlyWhenActiveAndConversationShownWithBothBoundaries() = runTest {
        val (h, server, store) = make {
            it.received("a1", "peer-a", 0, unread = false)
            it.received("a2", "peer-a", 10, unread = true)
            it.poke("p1", "peer-a", 12)
            it.poke("p2", "peer-a", 14)
            it.poke("p3", "peer-a", 20, mine = true, kind = "ultra")
            it.poke("q1", "peer-b", 30)
        }
        // background 에서 대화가 서도 읽음을 올리지 않는다.
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(0, h.count("mark_conversation_read"), "앱이 active 가 아닌데 읽음을 올렸다")
        // 목록만 떠 있으면(다른 대화) 올리지 않는다.
        store.conversationDidDisappear("t1")
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        assertEquals(0, h.count("mark_conversation_read"), "대화 화면이 없는데 읽음을 올렸다")
        assertEquals(setOf(peerA, peerB), store.unreadPokePeerIDs)
        assertEquals(setOf(peerA), store.unreadPeerIDs)
        // 그 대화가 active 로 떠 있을 때 — 한 번, 경계 둘(마지막 받은 메시지 · 마지막 **받은** 찌르기).
        store.conversationDidAppear(peerA, "t2")
        advanceUntilIdle()
        val marks = bodies(h, "mark_conversation_read")
        assertEquals(1, marks.size)
        val body = SwiftJson.parse(marks.single()) as JsonObject
        assertEquals("peer-a", body["p_peer"]!!.jsonPrimitive.content)
        assertEquals("a2", body["p_through_message"]!!.jsonPrimitive.content)
        assertEquals("p2", body["p_through_poke"]!!.jsonPrimitive.content, "찌르기 경계가 마지막 받은 찌르기가 아니다")
        // 낙관 읽음: 응답 전후로 점이 꺼지고, 아직 안 연 사람은 그대로.
        assertEquals(setOf(peerB), store.unreadPokePeerIDs)
        assertEquals(emptySet(), store.unreadPeerIDs)
        assertEquals(0, store.badgeCount)
        assertEquals(0, h.count("mark_messages_read"))
        h.assertClean()
    }

    @Test
    fun pokeOnlyMarkOmitsMessageBoundaryKey() = runTest {
        val (h, _, store) = make {
            it.received("a1", "peer-a", 0, unread = false)
            it.poke("p1", "peer-a", 4)
        }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val body = bodies(h, "mark_conversation_read").single()
        assertTrue(body.contains(""""p_through_poke":"p1""""), body)
        assertFalse(body.contains("p_through_message"), "안 움직여야 할 메시지 갈래에 키를 실었다: $body")
        h.assertClean()
    }

    @Test
    fun legacyServerFoldsMarkToOldFunctionAndHistoryChain() = runTest {
        val (h, server, store) = make {
            it.missing += "message_history_with_pokes"
            it.missing += "mark_conversation_read"
            it.received("a1", "peer-a", 0)
            it.received("a2", "peer-a", 10)
            it.poke("p1", "peer-a", 12)
        }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertTrue(h.count("message_history_with_reads") >= 1, "새 RPC 가 없으면 with_reads 로 접는다")
        assertEquals(h.count("message_history_with_pokes"), h.count("message_history_with_reads"), "새 RPC 를 매번 먼저 묻는다(폴백을 캐시하지 않는다)")
        assertFalse(store.pokeLogAvailable)
        assertEquals(emptyList(), store.pokeLog, "옛 서버에서는 찌르기 줄이 없다")
        assertEquals(1, h.count("mark_messages_read"))
        assertEquals(1, h.count("mark_conversation_read"), "새 함수를 먼저 시도한다")
        val body = bodies(h, "mark_messages_read").single()
        assertTrue(body.contains(""""p_through":"a2""""), body)
        assertFalse(body.contains("p_through_poke"))
        // 그것도 없으면 옛 이력(읽음 모름) — 1 을 그리지 않는다.
        server.missing += "message_history_with_reads"
        store.refreshNow()
        advanceUntilIdle()
        assertTrue(h.count("message_history") >= 1)
        assertFalse(store.readReceiptsAvailable)
        h.assertClean()
    }

    @Test
    fun serverForgettingPokesClearsGhostRows() = runTest {
        val (h, server, store) = make {
            it.received("a1", "peer-a", 0, unread = false)
            it.poke("p1", "peer-b", 2)
        }
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        assertTrue(store.pokeLogAvailable)
        assertEquals(listOf(peerB, peerA), store.threadItems(h.now()).map { it.peerUserID }, "찌르기만 있는 사람(안 읽음)이 위")
        server.missing += "message_history_with_pokes"
        store.refreshNow()
        advanceUntilIdle()
        assertFalse(store.pokeLogAvailable)
        assertEquals(emptyMap(), store.pokeChronology)
        assertEquals(listOf(peerA), store.threadItems(h.now()).map { it.peerUserID }, "유령 찌르기 줄이 남았다")
        h.assertClean()
    }

    // ---------------------------------------------------------------- ③ 겹치지 않는다 · 늦은 응답은 순서 번호로

    @Test
    fun overlappingRefreshesCoalesceAndLateHistoryCannotEraseNewerRows() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0) }
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        val firstGate = CompletableDeferred<Unit>()
        server.historyGate = firstGate
        // 이력 조회 하나가 떠 있는 동안 세 계기 — 뒤따르는 한 번으로 합친다.
        val job = store.requestActivityRefresh(includeHistory = true)
        runCurrent()
        assertTrue(store.requestActivityRefresh(includeHistory = true) === job)
        store.realtimeMessageActivity()
        store.didReceiveMessagePush(peerA)
        server.historyGate = null
        server.received("a2", peerA, 5)
        firstGate.complete(Unit)
        advanceUntilIdle()
        assertEquals(3, h.count("message_history_with_pokes"), "첫 표시 1 + 떠 있던 1 + 합친 1 — 계기 셋이 셋을 띄우지 않는다")
        assertEquals(listOf("a1", "a2"), store.history.map { it.id })
        // 먼저 띄운 이력이 늦게 와도 나중 이력이 그린 새 줄을 지우지 않는다(맥 M4).
        val lateGate = CompletableDeferred<Unit>()
        server.historyGate = lateGate
        val late = launch { store.performLoadHistory() }
        runCurrent()
        server.historyGate = null
        server.received("a3", peerA, 9)
        store.performLoadHistory()
        assertEquals(listOf("a1", "a2", "a3"), store.history.map { it.id })
        server.rows.removeAt(server.rows.lastIndex)
        lateGate.complete(Unit)
        late.join()
        assertEquals(listOf("a1", "a2", "a3"), store.history.map { it.id }, "늦은 옛 응답이 새 줄을 지웠다")
        h.assertClean()
    }

    /**
     * ③ 요약도 순서 번호로(검증 V08): 먼저 띄운 요약(옛 값 — 안 읽음 3)이 나중 요약(새 값 — 안 읽음 1)보다 늦게 와도 새 요약을 덮지 않는다.
     * 기준선: 늦은 응답이 실제로 도착했다(요청 둘 · 가상 시간 그대로 = 시한이 아니라 늦은 응답).
     */
    @Test
    fun lateOldSummaryCannotOverwriteNewerSummary() = runTest {
        val (h, server, store) = make()
        server.summary = """{"status":"ok","total":3,"peers":[{"peer_user_id":"peer-a","count":3,"last_epoch_ms":1}]}"""
        val lateGate = CompletableDeferred<Unit>()
        server.summaryGate = lateGate
        val late = launch { store.performLoadSummary() }
        runCurrent()
        val startedAt = testScheduler.currentTime
        server.summaryGate = null
        server.summary = """{"status":"ok","total":1,"peers":[{"peer_user_id":"peer-b","count":1,"last_epoch_ms":2}]}"""
        store.performLoadSummary()
        val newer = store.summary!!
        assertEquals(1L, newer.summary.total)
        assertEquals(1, store.badgeCount)
        lateGate.complete(Unit)
        late.join()
        assertEquals(startedAt, testScheduler.currentTime, "멈춘 요약이 시한에 걸렸다(늦은 응답을 재지 못했다)")
        assertEquals(2, h.count("message_unread_summary"))
        assertEquals(newer, store.summary, "늦게 온 옛 요약이 새 요약을 덮었다")
        assertEquals(1, store.badgeCount, "늦은 옛 요약이 배지를 3 으로 되돌렸다")
        assertEquals(mapOf(peerB to 1), store.unreadCountsByPeer)
        h.assertClean()
    }

    // ---------------------------------------------------------------- ④ 열린 대화는 곧바로 · 닫힌 대화는 낡음

    @Test
    fun openConversationFetchesHistoryAtOnceClosedOnlySummary() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0, unread = false) }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val before = h.count("message_history_with_pokes")
        server.received("a2", peerA, 5)
        store.realtimeMessageActivity()
        runCurrent()
        advanceTimeBy(500)
        assertEquals(before + 1, h.count("message_history_with_pokes"), "열린 대화는 신호 뒤 곧바로 이력(스로틀 없음)")
        assertEquals(listOf("a1", "a2"), store.history.map { it.id })
        assertEquals("a2", bodies(h, "mark_conversation_read").lastOrNull()?.let { (SwiftJson.parse(it) as JsonObject)["p_through_message"]!!.jsonPrimitive.content })
        store.conversationDidDisappear("t1")
        advanceUntilIdle()
        val history = h.count("message_history_with_pokes")
        val summaries = h.count("message_unread_summary")
        store.realtimeMessageActivity()
        advanceUntilIdle()
        assertEquals(history, h.count("message_history_with_pokes"), "닫힌 대화에 이력을 받았다")
        assertEquals(summaries + 1, h.count("message_unread_summary"))
        assertTrue(store.isHistoryStale)
        h.assertClean()
    }

    // ---------------------------------------------------------------- ⑤ 세대 가드

    @Test
    fun lateResponsesAfterSignOutDoNotTouchNextAccount() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0) }
        store.appDidBecomeActive()
        store.setDraft("쓰던 글", peerA)
        val gate = CompletableDeferred<Unit>()
        server.historyGate = gate
        store.listDidAppear()
        runCurrent()
        h.session.signOut()
        store.reset()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(emptyList(), store.history, "로그아웃 뒤 도착한 이력이 들어왔다")
        assertFalse(store.historyLoaded)
        assertEquals("", store.draft(peerA))
        assertNull(store.summary)
        h.assertClean()
    }

    /**
     * ⑤ 세대 가드 그 자체: 작업 취소가 닿지 않는 조회(앱 조립이 직접 부른 performLoadHistory — 취소보다 응답이 먼저 메인 차례를 기다리던 창)도
     * 다음 계정 화면에 들어가지 않는다. 위 시험은 reset 의 작업 취소가 먼저 막아 이 가드를 재지 못한다(결함 심기 M06 실측).
     */
    @Test
    fun generationGuardDropsLateHistoryEvenWithoutCancellation() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0) }
        val gate = CompletableDeferred<Unit>()
        server.historyGate = gate
        val late = launch { store.performLoadHistory() }
        runCurrent()
        val startedAt = testScheduler.currentTime
        h.session.signOut()
        store.reset()
        gate.complete(Unit)
        late.join()
        // 가상 시간이 흐르지 않았다 = 멈춘 조회는 HTTP 시한이 아니라 **늦은 응답**으로 끝났다(가드가 실제로 재졌다).
        assertEquals(startedAt, testScheduler.currentTime)
        assertEquals(1, h.count("message_history_with_pokes"))
        assertEquals(emptyList(), store.history, "로그아웃 뒤 도착한 이력이 다음 계정 화면에 들어왔다")
        assertFalse(store.historyLoaded)
        assertNull(store.historySnapshot)
        h.assertClean()
    }

    // ---------------------------------------------------------------- 보내기

    @Test
    fun sendClearsDraftAtOncePendingThenServerRowFailureRestoresDraft() = runTest {
        val (h, server, store) = make { it.received("a1", "peer-a", 0, unread = false) }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        store.setDraft("  안녕하세요  ", peerA)
        assertFalse(store.sendDraft(peerA, isComposing = true), "조합 중에는 보내지 않는다")
        assertTrue(store.sendDraft(peerA, isComposing = false))
        assertEquals("", store.draft(peerA))
        assertEquals(listOf("안녕하세요"), store.pendingOutgoing.map { it.body })
        server.sent("s1", peerA, 600, body = "안녕하세요")
        advanceUntilIdle()
        assertEquals(""""p_to":"peer-a","p_body":"안녕하세요"""", bodies(h, "send_message").single().removePrefix("{").removeSuffix("}"))
        assertEquals(emptyList(), store.pendingOutgoing, "진짜 행이 서면 자리 말풍선은 사라진다")
        // 거절: 글은 입력칸으로 · 문구는 코어 문장 · 자리 말풍선은 거둔다.
        server.sendReply = Reply.Json("""{"status":"target_focused"}""")
        store.setDraft("두 번째", peerA)
        store.sendDraft(peerA, isComposing = false)
        advanceUntilIdle()
        assertEquals("두 번째", store.draft(peerA))
        assertEquals("지금 집중 중이에요. 나중에 보내 주세요", store.sendNotices[peerA])
        assertEquals(emptyList(), store.pendingOutgoing)
        // 이모티콘 실패는 입력칸을 건드리지 않는다(쓰던 글을 덮지 않는다).
        server.sendReply = Reply.Offline
        store.setDraft("쓰던 글", peerA)
        assertTrue(store.sendSticker(AingSticker.joy, peerA))
        advanceUntilIdle()
        assertEquals("쓰던 글", store.draft(peerA))
        assertEquals("연결이 불안정해요. 잠시 후 다시 시도해 주세요", store.sendNotices[peerA])
        assertEquals(""""p_to":"peer-a","p_body":"[아잉:기쁨]"""", bodies(h, "send_message").last().removePrefix("{").removeSuffix("}"))
        h.assertClean()
    }

    // ---------------------------------------------------------------- 정렬 · 줄(INV)

    @Test
    fun threadRowsStandForPokeOnlyPeersAndCountBadgeIsMessageOnly() = runTest {
        val (h, server, store) = make {
            it.received("a1", "peer-a", 0, unread = true)
            it.poke("p1", "peer-b", 3, name = "한결")
        }
        server.summary = """{"status":"ok","total":1,"peers":[{"peer_user_id":"peer-a","count":1}]}"""
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        val rows = store.threadItems(h.now())
        val pokeOnly = rows.single { it.peerUserID == peerB }
        assertEquals(emptyList(), pokeOnly.thread.messages, "찌르기만 있는 사람도 줄이 선다")
        assertTrue(pokeOnly.isUnread)
        assertNull(pokeOnly.countBadge, "찌르기뿐인 줄에 안 읽은 메시지 숫자를 붙였다")
        assertEquals("한결님이 콕 찔렀어요", pokeOnly.previewText)
        assertEquals("1", rows.single { it.peerUserID == peerA }.countBadge)
        assertEquals(1, store.badgeCount, "탭 배지는 메시지만 센다")
        assertEquals(setOf(peerA, peerB), store.sortUnreadPeerIDs)
        assertEquals(setOf(peerA), store.unreadPeerIDs)
        h.assertClean()
    }

    @Test
    fun blockHidesAtOnceFailureRestoresAndPokeRowsFollowTheGate() = runTest {
        val (h, server, store) = make {
            it.received("a1", "peer-a", 0)
            it.poke("p1", "peer-a", 2)
            it.poke("q1", "peer-b", 3)
        }
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        server.blockReply = Reply.serverDown
        store.blockPeer(peerA)
        assertTrue(store.isHiddenByBlock(peerA))
        assertEquals(listOf(peerB), store.threadItems(h.now()).map { it.peerUserID }, "숨긴 사람이 찌르기로 줄을 세웠다")
        assertEquals(emptyList(), store.pokeLog(peerA))
        assertEquals(0, store.badgeCount)
        advanceUntilIdle()
        assertFalse(store.isHiddenByBlock(peerA), "실패하면 대화가 돌아온다")
        assertEquals("차단하지 못했어요 — 연결을 확인하고 다시 시도해 주세요", store.blockNotice)
        assertTrue(store.blockNoticeIsError)
        server.blockReply = Reply.Json("{}")
        store.blockPeer(peerA)
        advanceUntilIdle()
        assertTrue(store.isHiddenByBlock(peerA))
        assertEquals(listOf("""{"p_user":"peer-a"}"""), bodies(h, "block_user").distinct())
        h.assertClean()
    }
}
