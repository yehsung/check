// 원본: Tests/checkTests/V0365MessagePokeTests.swift(④⑤⑥ 받은 찌르기 · 보낸 찌르기) · Tests/checkTests/V0331MessageArrivalTests.swift(M4 즉시 삽입) @ 39199b07
// Windows 공용 패치 3(xplat-w1/briefs/poke.md §6 요청 B · §4 ConsumedRowsSink): 데스크톱이 take_pokes 로 소비한 행을 메시지 기록에 넣는 문.
// 명세 번호: P14(받은 찌르기 — 24h · 중복 · 차단 · MessagePokeLogKind · 안 읽음) · M4(보이는 대화 즉시 삽입 · m4-fix 도착 순서 · 생존 규칙).
// 음성 대조(규칙 하나를 깨면 빨강)는 시험마다 주석의 [음성] 줄이 가리킨다.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageUnreadRules
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogKind
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.ceil
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesStoreConsumedTest {
    private val peerA = "peer-a"
    private val peerB = "peer-b"

    private suspend fun TestScope.make(setup: (MessagesServer) -> Unit = {}): Triple<StoreHarness, MessagesServer, MessagesStore> {
        val server = MessagesServer().also(setup)
        val h = StoreHarness(this) { server.route(it) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        return Triple(h, server, store)
    }

    /** take_pokes 소비 행(합성). [at] 은 [MessagesServer.base] 기준 초 — 서버 행과 같은 눈금. */
    private fun MessagesServer.taken(id: String, from: String, at: Long, kind: String? = "normal", name: String = "상대", body: String? = null) =
        TakenPokeRow(id = id, fromUser = from, fromDisplayName = name, createdEpoch = base + at, kind = kind, body = body)

    private fun bodies(h: StoreHarness, rpc: String): List<JsonObject> =
        h.storeRequests.filter { it.rpcName == rpc }.map { SwiftJson.parse(it.bodyText) as JsonObject }

    // ================================================================ 받은 찌르기(P14 — WorkTimerStoreMessagePokes.swift 106-150)

    /**
     * Swift `받은_찌르기는_왕복_없이_목록과_대화에`: 대화가 안 떠 있으면 목록 안 읽음에 곧바로(왕복 0), 그 사람과의 대화가 떠 있으면 그 자리에 줄이 서고
     * 그 찌르기까지 읽음이 오른다. 24시간 밖의 것은 안 넣는다.
     * [음성] 24h 창 비교를 지우면 "old" 가 들어가 넣은 개수가 2 가 된다.
     */
    @Test
    fun consumedPokesEnterLogWithoutRoundTripAndMarkWhenSeen() = runTest {
        val (h, server, store) = make { it.received("m1", peerA, 0, unread = false) }
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        assertNotNull(store.pokeSnapshot, "전제: 새 서버 — 찌르기 기록을 안다")
        val historyBefore = h.count("message_history_with_pokes")

        // ① 대화가 안 떠 있다 — 목록 합집합에 곧바로(왕복 0).
        server.poke("tb", peerB, 580, name = "지수")
        assertEquals(1, store.insertConsumedPokes(listOf(server.taken("tb", peerB, 580, name = "지수"))))
        assertEquals(setOf(peerB), store.unreadPokePeerIDs, "받은 찌르기가 목록 안 읽음에 안 들었다")
        assertEquals(listOf("tb"), store.pokeLog.map { it.id })
        assertEquals(true, store.pokeLog.single().isUnread)
        assertEquals(historyBefore, h.count("message_history_with_pokes"), "받은 찌르기 하나에 이력을 다시 받았다")

        // ② A 와의 대화가 active 로 떠 있다 — 그 자리에 줄이 서고 그 찌르기까지 읽음이 오른다.
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val historyOpen = h.count("message_history_with_pokes")
        server.poke("ta", peerA, 595, kind = "ultra", name = "민수")
        val old = TakenPokeRow("old", peerA, "민수", null, (h.now().timeIntervalSince1970 - 25 * 3600).toLong(), "normal")
        val inserted = store.insertConsumedPokes(listOf(server.taken("ta", peerA, 595, kind = "ultra", name = "민수"), old))
        assertEquals(1, inserted, "24시간 밖의 찌르기를 넣었다")
        assertEquals(listOf("ta"), store.pokeLog(peerA).map { it.id })
        assertEquals(MessagePokeLogKind.ultra, store.pokeLog(peerA).single().kind)
        assertEquals(historyOpen, h.count("message_history_with_pokes"), "보이는 대화의 찌르기가 이력 왕복을 불렀다")
        advanceUntilIdle()
        assertEquals("ta", bodies(h, "mark_conversation_read").last()["p_through_poke"]!!.jsonPrimitive.content)
        assertEquals(setOf(peerB), store.unreadPokePeerIDs)
        h.assertClean()
    }

    /**
     * Swift `즉시_넣은_찌르기는_나중_이력만_덮는다`: 넣기 **전에** 띄운 이력 응답은 방금 넣은 찌르기를 지우지 않고, 나중에 띄운 응답의 서버 행이 이긴다.
     * [음성] applyPokeLog 의 생존분(kept)을 빼면 첫 단언이 빨갛다.
     */
    @Test
    fun consumedPokeSurvivesEarlierHistoryAndLaterServerRowWins() = runTest {
        val (h, server, store) = make()
        store.performLoadHistory()
        assertNotNull(store.pokeSnapshot)
        val gate = CompletableDeferred<Unit>()
        server.historyGate = gate
        val early = launch { store.performLoadHistory() }   // 넣기 **전에** 띄운 조회 — 문에 붙잡힌다
        runCurrent()
        server.historyGate = null
        assertEquals(1, store.insertConsumedPokes(listOf(server.taken("tp", peerA, 597, name = "민수"))))
        gate.complete(Unit)
        early.join()
        assertEquals(listOf("tp"), store.pokeLog.map { it.id }, "먼저 띄운 조회가 방금 넣은 찌르기를 지웠다")
        assertEquals(1, store.pendingLocalPokeArrivalCount)

        server.poke("tp", peerA, 597, unread = false, name = "민수")
        store.performLoadHistory()
        assertEquals(listOf("tp"), store.pokeLog.map { it.id })
        assertEquals(false, store.pokeLog.single().isUnread, "나중에 띄운 조회의 서버 행이 안 이겼다")
        assertEquals(emptySet(), store.unreadPokePeerIDs)
        assertEquals(0, store.pendingLocalPokeArrivalCount, "서버가 답한 뒤에도 즉시 삽입 장부가 남았다")
        h.assertClean()
    }

    /**
     * Swift `받은_찌르기의_종류는_이력과_같은_규칙`: 'message' · 모르는 종류는 넣지 않는다. 같은 글자를 두 길(즉시 삽입 · 이력 디코더)이 같은 쪽으로
     * 가른다. kind 가 없는 옛 행만 일반 찌르기다.
     * [음성] `MessagePokeLogKind.of` 대신 `PokeKind.of`(모르면 normal)로 가르면 sticker 가 들어가 ① 이 빨갛다.
     */
    @Test
    fun consumedPokeKindsFollowHistoryDecoder() = runTest {
        val (h, server, store) = make {
            it.poke("d-sticker", peerB, 1, kind = "sticker")
            it.poke("d-normal", peerB, 2, kind = "normal")
            it.poke("d-ultra", peerB, 3, kind = "ultra")
        }
        store.performLoadHistory()
        val decoded = store.pokeLog.associate { it.id to it.kind }
        // ① 모르는 종류 · 메시지: 기록에도, 목록 안 읽음에도 안 든다.
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("t-sticker", peerA, 590, "sticker"), server.taken("t-message", peerA, 590, "message"))))
        assertTrue(store.pokeLog(peerA).isEmpty(), "모르는 종류를 콕 기록에 넣었다")
        assertFalse(peerA in store.unreadPokePeerIDs, "모르는 종류가 목록 맨 위 안 읽음으로 셌다")
        // ② 즉시 삽입과 이력 디코더가 같은 쪽으로 가른다.
        for (kind in listOf("sticker", "normal", "ultra")) {
            val inserted = store.insertConsumedPokes(listOf(server.taken("p-$kind", peerA, 591, kind)))
            val insertedKind = if (inserted == 1) store.pokeLog.first { it.id == "p-$kind" }.kind else null
            assertEquals(decoded["d-$kind"], insertedKind, "'$kind': 즉시 삽입 ≠ 이력 디코더")
        }
        // ③ 종류 칸이 없는 옛 행은 일반 찌르기다.
        assertEquals(1, store.insertConsumedPokes(listOf(server.taken("t-legacy", peerA, 592, kind = null))))
        assertEquals(MessagePokeLogKind.poke, store.pokeLog.first { it.id == "t-legacy" }.kind)
        h.assertClean()
    }

    /**
     * Swift `옛_서버면_지금처럼`의 끝 단언: 서버가 찌르기 기록을 모르면(옛 조회로 접음 · 아직 이력 전) 넣지 않는다 — 다음 이력에서 사라질 줄이다.
     * [음성] `pokeSnapshot == null` 가드를 빼면 1 이 나온다.
     */
    @Test
    fun consumedPokesSkippedWhileServerDoesNotKnowPokeLog() = runTest {
        val (h, server, store) = make { it.missing += "message_history_with_pokes" }
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("tp0", peerA, 590))), "이력 전(스냅숏 없음)에 넣었다")
        store.performLoadHistory()
        assertFalse(store.pokeLogAvailable)
        assertNull(store.pokeSnapshot)
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("tp", peerA, 590))), "옛 서버에서 받은 찌르기를 기록에 넣었다")
        assertTrue(store.pokeLog.isEmpty())
        assertEquals(0, store.pendingLocalPokeArrivalCount)
        h.assertClean()
    }

    /**
     * P14 의 거름 셋 — 음성 대조 ①24h 경계 ②중복 id ③차단. 경계는 `createdAt >= now − 24h`(같으면 넣는다).
     * [음성] ① `<` 를 `<=` 로 바꾸면 경계 행이 빠져 빨강 ② known 검사를 빼면 서버 행이 안 읽음 줄로 하나 더 선다 ③ 차단 검사를 빼면 B 가 든다.
     */
    @Test
    fun consumedPokesRespect24hBoundaryDuplicatesAndBlocks() = runTest {
        val (h, server, store) = make { it.poke("dup", peerA, 100, unread = false) }
        store.performLoadHistory()
        assertEquals(listOf("dup"), store.pokeLog.map { it.id })

        // ① 24시간 경계: 정확히 24시간 전은 들고, 그보다 1초 앞은 안 든다.
        val nowEpoch = h.now().timeIntervalSince1970
        assertEquals(ceil(nowEpoch), nowEpoch, "전제: 시계가 정수 초 — 경계 행이 정확히 now − 24h 다")
        val edge = nowEpoch.toLong() - 24 * 3600
        val rows = listOf(
            TakenPokeRow("edge", peerA, "민수", null, edge, "normal"),
            TakenPokeRow("past", peerA, "민수", null, edge - 1, "normal"),
        )
        assertEquals(1, store.insertConsumedPokes(rows))
        assertEquals(listOf("edge", "dup"), store.pokeLog.map { it.id })

        // ② 이미 있는 id 는 건드리지 않는다(서버 행 — 읽음 — 이 그대로).
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("dup", peerA, 100))))
        assertEquals(1, store.pokeLog.count { it.id == "dup" })
        assertEquals(false, store.pokeLog.first { it.id == "dup" }.isUnread, "중복 행이 서버 행을 안 읽음으로 덮었다")

        // ③ 차단으로 걷어낸 사람의 찌르기는 넣지 않는다 — 같은 행이 A 에게서 오면 든다(대조).
        store.blockPeer(peerB)
        advanceUntilIdle()
        assertTrue(store.isHiddenByBlock(peerB))
        val before = store.pokeLog.size
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("blk", peerB, 590))), "차단한 사람의 찌르기를 넣었다")
        assertEquals(before, store.pokeLog.size)
        assertFalse(peerB in store.unreadPokePeerIDs)
        assertEquals(1, store.insertConsumedPokes(listOf(server.taken("ok", peerA, 590))))
        // 빈 id · 빈 보낸이도 넣지 않는다.
        assertEquals(0, store.insertConsumedPokes(listOf(server.taken("", peerA, 591), server.taken("noone", "", 591))))
        h.assertClean()
    }

    /**
     * 도착 번호(m4-fix 의 찌르기 짝): 같은 초에 온 두 찌르기는 id 사전순이 아니라 take_pokes 행 순서로 서고, 읽음 경계는 나중 것이다.
     * [음성] 정렬에 도착표를 넘기지 않으면 id 순(a-second → z-first)으로 뒤집혀 빨강.
     */
    @Test
    fun sameSecondConsumedPokesKeepTakeOrderAndMarkTheLast() = runTest {
        val (h, server, store) = make()
        store.appDidBecomeActive()
        store.performLoadHistory()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        server.poke("z-first", peerA, 598)
        server.poke("a-second", peerA, 598)
        assertEquals(2, store.insertConsumedPokes(listOf(server.taken("z-first", peerA, 598), server.taken("a-second", peerA, 598))))
        assertEquals(listOf("z-first", "a-second"), store.pokeLog(peerA).map { it.id }, "같은 초 도착 순서가 id 순으로 뒤집혔다")
        advanceUntilIdle()
        assertEquals("a-second", bodies(h, "mark_conversation_read").first()["p_through_poke"]!!.jsonPrimitive.content)
        h.assertClean()
    }

    // ================================================================ 보낸 찌르기(WorkTimerStoreMessagePokes.swift 151-155)

    /**
     * Swift `보낸_찌르기는_그_대화가_떠_있을_때만_이력_한_번`: 그 사람과의 대화가 떠 있을 때만 이력 한 번. 다른 사람 · 닫힌 대화는 받지 않는다.
     * [음성] 상대 비교를 빼면 B 를 찔렀을 때도 이력을 받아 빨강.
     */
    @Test
    fun refreshAfterPokeSentOnlyForTheOpenConversation() = runTest {
        val (h, _, store) = make()
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val before = h.count("message_history_with_pokes")
        assertNotNull(store.refreshConversationAfterPokeSent(peerA))
        advanceUntilIdle()
        assertEquals(before + 1, h.count("message_history_with_pokes"), "보이는 대화의 상대를 찔렀는데 기록을 안 받았다")

        assertNull(store.refreshConversationAfterPokeSent(peerB), "다른 사람을 찔렀는데 이 대화를 다시 받았다")
        store.conversationDidDisappear("t1")
        assertNull(store.refreshConversationAfterPokeSent(peerA), "대화를 닫은 뒤 찔렀는데 받았다")
        advanceUntilIdle()
        assertEquals(before + 1, h.count("message_history_with_pokes"))
        h.assertClean()
    }

    // ================================================================ 받은 메시지(M4 — WorkTimerStoreMessages.swift 1013-1083)

    /**
     * Swift `보이는_대화에는_take_pokes_응답만으로_새_말이_들어간다_추가_왕복_0`(★ 재는 순간: 응답 반영 직후, 추가 왕복 전) +
     * `receiveConsumedMessages` ③(소비한 메시지가 있으면 도착 새로고침 1회).
     * [음성] receiveConsumedMessages 에서 삽입을 빼면 ★ 단언이 빨갛다.
     */
    @Test
    fun consumedMessageEntersVisibleConversationImmediately() = runTest {
        val (h, server, store) = make { it.received("m0", peerA, 0, unread = false) }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val historyBefore = h.count("message_history_with_pokes")
        val summaryBefore = h.count("message_unread_summary")
        server.received("m1", peerA, 599, unread = true, body = "밥?")   // 서버도 안다(소비는 표시와 무관 — 기록은 24시간 남는다)

        store.receiveConsumedMessages(listOf(server.taken("m1", peerA, 599, kind = "message", body = "밥?")), h.now())
        // ★ 추가 왕복 전.
        assertEquals(listOf("m0", "m1"), store.history.map { it.id }, "보이는 대화에 take_pokes 응답만으로 안 들어갔다")
        assertEquals(true, store.history.last().isUnread)
        assertEquals(historyBefore, h.count("message_history_with_pokes"))

        advanceUntilIdle()
        assertTrue(h.count("message_unread_summary") > summaryBefore, "도착이 요약(점)을 안 받았다")
        val marks = bodies(h, "mark_messages_read") + bodies(h, "mark_conversation_read")
        assertTrue(marks.any { it.toString().contains("\"m1\"") }, "보고 있는 대화의 새 말을 읽음으로 안 올렸다: $marks")
        assertEquals(listOf("m0", "m1"), store.history.map { it.id })
        assertEquals(0, store.pendingLocalArrivalCount, "서버가 답한 뒤에도 즉시 삽입 장부가 남았다")
        h.assertClean()
    }

    /**
     * Swift `다른_대화나_닫힌_대화에는_넣지_않는다`(other-peer · panel-closed): 넣지 않되 도착 새로고침(요약)은 부른다. 닫힌 대화에는 이력을 붙이지 않는다.
     * [음성] 상대 비교를 빼면 other-peer 에서 B 의 대화에 A 의 말이 들어가 빨강.
     */
    @Test
    fun consumedMessageSkipsOtherOrClosedConversationButRefreshesSummary() = runTest {
        for (situation in listOf("other-peer", "closed")) {
            val (h, server, store) = make { it.received("m0", peerA, 0, unread = false) }
            store.appDidBecomeActive()
            if (situation == "other-peer") store.conversationDidAppear(peerB, "t1")
            advanceUntilIdle()
            val historyBefore = h.count("message_history_with_pokes")
            val summaryBefore = h.count("message_unread_summary")
            store.receiveConsumedMessages(listOf(server.taken("m1", peerA, 599, kind = "message", body = "밥?")), h.now())
            assertFalse(store.history.any { it.id == "m1" }, "$situation: 안 보이는 대화에 즉시 넣었다")
            assertEquals(0, store.pendingLocalArrivalCount)
            advanceUntilIdle()
            assertEquals(summaryBefore + 1, h.count("message_unread_summary"), "$situation: 도착이 요약(점)을 안 받았다")
            val expectedHistory = if (situation == "other-peer") historyBefore + 1 else historyBefore
            assertEquals(expectedHistory, h.count("message_history_with_pokes"), "$situation: 이력 조회 수")
            h.assertClean()
        }
    }

    /**
     * Swift `중복_id_는_넣지_않고_같은_초의_새_말은_서버가_아는_말_뒤에_선다`: 중복은 한 번만, 서버 행이 이긴다, 같은 초의 새 말은 서버가 아는 말 뒤에
     * 도착 순서로, 멱등, 읽음 경계는 즉시 삽입한 마지막 말.
     * [음성] known 검사를 빼면 2 가 3 이 되어 빨강.
     */
    @Test
    fun duplicateMessageSkippedAndSameSecondArrivalsFollowServerKnown() = runTest {
        val (h, server, store) = make { it.received("z-known", peerA, 599, unread = false, body = "서버가 아는 말") }
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val entries = MessagesStore.consumedMessageEntries(
            listOf(
                server.taken("a-new", peerA, 599, kind = "message", body = "첫째"),
                server.taken("b-new", peerA, 599, kind = "message", body = "둘째"),
                server.taken("z-known", peerA, 599, kind = "message", body = "중복"),
            ),
            receiptsKnown = true,
        )
        assertEquals(2, store.insertConsumedMessagesIntoVisibleConversation(entries), "중복 id 를 한 번 더 넣었다")
        assertEquals(listOf("z-known", "a-new", "b-new"), store.history.map { it.id })
        assertEquals("서버가 아는 말", store.history.first().body, "중복 행이 서버 행을 덮었다")
        assertEquals(0, store.insertConsumedMessagesIntoVisibleConversation(entries))
        assertEquals(listOf("z-known", "a-new", "b-new"), store.history.map { it.id })
        assertEquals("b-new", MessageUnreadRules.markTarget(peerA, store.history, store.historySnapshot!!, null))
        advanceUntilIdle()
        h.assertClean()
    }

    /**
     * Swift `삽입보다_먼저_띄운_이력이_먼저_반영돼도_새_말은_남고_나중_조회에_없으면_서버가_이긴다`.
     * [음성] performLoadHistory 의 생존분(kept)을 빼면 첫 단언이 빨갛다.
     */
    @Test
    fun insertedMessageSurvivesEarlierHistoryButLaterServerWins() = runTest {
        val (h, server, store) = make { it.received("m0", peerA, 0, unread = false) }
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        val gate = CompletableDeferred<Unit>()
        server.historyGate = gate
        val early = launch { store.performLoadHistory() }
        runCurrent()
        server.historyGate = null
        val row = server.taken("m1", peerA, 600, kind = "message", body = "지금")
        assertEquals(1, store.insertConsumedMessagesIntoVisibleConversation(MessagesStore.consumedMessageEntries(listOf(row), receiptsKnown = true)))
        gate.complete(Unit)
        early.join()
        assertEquals(listOf("m0", "m1"), store.history.map { it.id }, "삽입 전에 띄운 이력이 반영되며 새 말을 지웠다")
        assertEquals(1, store.pendingLocalArrivalCount)

        store.performLoadHistory()
        assertEquals(listOf("m0"), store.history.map { it.id }, "삽입 뒤에 띄운 서버 이력에 없는데 로컬 행이 남았다(서버가 이겨야 한다)")
        assertEquals(0, store.pendingLocalArrivalCount)
        h.assertClean()
    }

    /**
     * `consumedMessageEntries` 의 거름(이력 행과 같은 옮김 규칙): 찌르기 행 · 보이는 글자 없음 · 보낸이 없음은 버리고, 이름은 "사용자"로 폴백,
     * 읽음을 모르는 서버면 isUnread = null. 메시지 행이 하나도 없으면 도착 새로고침을 부르지 않는다.
     * [음성] 종류 검사를 빼면 찌르기 행이 메시지로 들어가 빨강.
     */
    @Test
    fun consumedMessageEntriesFilterAndNoRefreshWithoutMessages() = runTest {
        val (h, server, store) = make()
        val entries = MessagesStore.consumedMessageEntries(
            listOf(
                // 찌르기 행에 글자가 실려 와도(합성) 메시지가 아니다 — 종류가 먼저 가른다.
                server.taken("p-normal", peerA, 1, body = "콕"),
                server.taken("p-ultra", peerA, 1, kind = "ultra", body = "번개"),
                server.taken("p-legacy", peerA, 1, kind = null, body = "옛"),
                server.taken("blank", peerA, 1, kind = "message", body = "  \n "),
                server.taken("nobody", "", 1, kind = "message", body = "누구"),
                server.taken("ok", peerA, 2, kind = "message", name = "", body = "  안녕 "),
            ),
            receiptsKnown = false,
        )
        assertEquals(listOf("ok"), entries.map { it.id })
        assertEquals("사용자", entries.single().peerName)
        assertEquals("안녕", entries.single().body)
        assertNull(entries.single().isUnread)

        store.appDidBecomeActive()
        advanceUntilIdle()
        val summaryBefore = h.count("message_unread_summary")
        store.receiveConsumedMessages(listOf(server.taken("p-only", peerA, 3)), h.now())
        advanceUntilIdle()
        assertEquals(summaryBefore, h.count("message_unread_summary"), "메시지 행이 없는데 도착 새로고침을 불렀다")
        h.assertClean()
    }
}
