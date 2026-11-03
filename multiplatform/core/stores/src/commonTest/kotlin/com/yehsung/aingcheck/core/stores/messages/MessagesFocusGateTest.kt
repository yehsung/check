// 원본: Tests/checkTests/FocusSendGateTests.swift(맥) · wt-phone-1017 62f9115c Tests/CheckMobileKitTests/V1017FocusSendGateMobileTests.swift(아이폰 1.0.17) — 판 7 Android 짝.
// 대표 결정(11-03, 되묻지 않는다): "대화는 열고 보내기만 막기" · "찌르기·메시지만"(확성기·게임 신청은 그대로) · "지금 서버에서도 막기".
// 서버 실출력: Tests/checkTests/Fixtures/directory-rpc(명부 8칸/7칸) · Tests/checkTests/Fixtures/sender-focus-rpc(sender_focused) — 스텁 추측이 아니다.
// 비교 기준선은 언제나 다르게 잡는다(memory comparison-baseline-must-differ): 켠 사람/끈 사람 · 켜짐 기억 있음/없음 · 게이트 켬/끔.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.stores.now.InMemoryTodoFileSystem
import com.yehsung.aingcheck.core.stores.now.ManualScheduler
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowStubServer
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesFocusGateTest {
    private val peerA = "peer-a"
    private val peerB = "peer-b"

    /** 서버 실출력(재생 하네스 · 8칸 = 운영 20261108120500 적용 뒤 · 7칸 = 그 전). 8칸에서 집중을 켠 사람은 하나다. */
    private val directory8 = RepoFiles.readText("Tests/checkTests/Fixtures/directory-rpc/app_user_directory__draft_8col.json")
    private val directory7 = RepoFiles.readText("Tests/checkTests/Fixtures/directory-rpc/app_user_directory__current_7col.json")
    private val focusedInFixture = "3e240c02-8972-478e-a674-014f498a641b"
    private val notFocusedInFixture = "544e3837-f01c-4560-b82f-4d44c269f044"
    private val senderFocusedReply = RepoFiles.readText("Tests/checkTests/Fixtures/sender-focus-rpc/send_message__sender_focused.json")

    /** 시험 조립: 메시지 서버 + 내 집중 GET + (있으면) 지금 탭 서버. 내 집중 응답은 [myFocus] 가 정한다. */
    private class Rig(
        val h: StoreHarness,
        val server: MessagesServer,
        val store: MessagesStore,
        val focus: FocusServer,
        val now: NowStore?,
        val scheduler: ManualScheduler?,
    ) {
        fun focusGets(): Int = h.storeRequests.count { isMyFocusGet(it) }
        fun sends(): Int = h.count("send_message")
    }

    private class FocusServer {
        var reply: Reply = Reply.Json("""[{"focus_mode":false}]""")
        var gate: CompletableDeferred<Unit>? = null
        fun route(r: RecordedRequest): Reply? {
            if (!isMyFocusGet(r)) return null
            return gate?.let { Reply.Gate(it, reply) } ?: reply
        }
    }

    private suspend fun TestScope.rig(
        gate: Boolean = true,
        withNow: Boolean = false,
        setup: (MessagesServer) -> Unit = {},
    ): Rig {
        val server = MessagesServer().also(setup)
        val focus = FocusServer()
        val nowServer = NowStubServer()
        val h = StoreHarness(this) { r -> focus.route(r) ?: server.route(r) ?: if (withNow) nowServer.route(r) else null }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" }, focusSendGate = gate)
        var now: NowStore? = null
        var scheduler: ManualScheduler? = null
        if (withNow) {
            scheduler = ManualScheduler()
            now = NowStore(h.context, h.storeScope, NowTodoStorage("/mem/now", InMemoryTodoFileSystem()), runsPeriodicRefresh = true, timers = scheduler)
            store.nowStore = now
            // 폰 조립(PhoneAppModel)과 같은 줄.
            now.onPeriodicTick = { store.refreshMyFocusModeIfFocused() }
        }
        return Rig(h, server, store, focus, now, scheduler)
    }

    // ---------------------------------------------------------------- 1. 보낸이 거절(sender_focused)

    @Test
    fun senderFocusedRejectionSpeaksMacSentenceRemembersAndBlocksTheNextPress() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.server.sendReply = Reply.Json(senderFocusedReply)
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(false, r.store.myFocusMode, "대화가 서면 내 집중을 묻는다(꺼짐)")
        r.store.setDraft("안녕하세요", peerA)
        assertTrue(r.store.sendDraft(peerA, isComposing = false))
        advanceUntilIdle()
        assertEquals(1, r.sends())
        // 문구는 iOS 코어 문장 그대로 · 글은 입력칸으로 · 보내는 중 말풍선은 거둔다.
        assertEquals(MessageNoticeText.senderFocused, r.store.sendNotices[peerA])
        assertEquals("집중 모드에서는 메시지를 보낼 수 없어요. 맥에서 집중을 끄면 보낼 수 있어요", r.store.sendNotices[peerA])
        assertEquals("안녕하세요", r.store.draft(peerA), "거절된 글이 입력칸으로 돌아오지 않았다")
        assertEquals(emptyList(), r.store.pendingOutgoing)
        // 기억: 다음 누름은 미리 막힌다(요청 0) — 글도 이모티콘도.
        assertEquals(true, r.store.myFocusMode)
        assertEquals(MessagesFocusBlock.myself, r.store.focusBlock(peerA))
        assertFalse(r.store.canSend(peerA))
        assertFalse(r.store.sendDraft(peerA, isComposing = false))
        assertFalse(r.store.canSendSticker(peerA))
        assertFalse(r.store.sendSticker(AingSticker.joy, peerA))
        advanceUntilIdle()
        assertEquals(1, r.sends(), "집중을 안 뒤에도 요청이 나갔다")
        assertEquals("안녕하세요", r.store.draft(peerA), "막힌 누름이 초안을 지웠다")
        assertEquals(MessageNoticeText.senderFocused, MessagesComposerRules.noticeLine(r.store.focusBlock(peerA), r.store.sendNotices[peerA]))
        r.h.assertClean()
    }

    /** ★ 기준선: 게이트가 꺼진 조립(Windows v1 동결)은 지금까지와 글자 그대로 같다 — 일반 안내 · 기억 없음 · 다음 누름도 나간다 · 내 집중 GET 0. */
    @Test
    fun gateOffAssemblyKeepsTheOldBehaviourExactly() = runTest {
        val r = rig(gate = false) { it.received("a1", peerA, 0, unread = false) }
        r.server.sendReply = Reply.Json(senderFocusedReply)
        r.server.directory = directory8
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        r.store.loadDirectory(force = true)
        advanceUntilIdle()
        assertEquals(0, r.focusGets(), "게이트가 꺼졌는데 내 집중을 물었다")
        assertNull(r.store.myFocusMode)
        r.store.setDraft("안녕", peerA)
        assertTrue(r.store.sendDraft(peerA, isComposing = false))
        advanceUntilIdle()
        assertEquals(MessageNoticeText.invalid, r.store.sendNotices[peerA], "꺼진 조립의 sender_focused 안내가 바뀌었다")
        assertNull(r.store.myFocusMode)
        assertTrue(r.store.sendDraft(peerA, isComposing = false), "꺼진 조립이 다음 누름을 막았다")
        advanceUntilIdle()
        assertEquals(2, r.sends())
        // 명부가 집중이라 말해도 꺼진 조립은 표시·잠금이 없다.
        assertFalse(r.store.isPeerFocused(focusedInFixture))
        r.store.setDraft("안녕", focusedInFixture)
        assertTrue(r.store.canSend(focusedInFixture))
        assertTrue(r.store.canSendSticker(focusedInFixture))
        assertNull(r.store.focusBlock(focusedInFixture))
        r.h.assertClean()
    }

    // ---------------------------------------------------------------- 2. 내 집중을 아는 길

    @Test
    fun myFocusOnFromServerBlocksEveryoneWithTheSameSentence() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.focus.reply = Reply.Json("""[{"focus_mode":true}]""")
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(true, r.store.myFocusMode)
        for (peer in listOf(peerA, peerB)) {
            r.store.setDraft("안녕", peer)
            assertEquals(MessagesFocusBlock.myself, r.store.focusBlock(peer))
            assertFalse(r.store.canSend(peer))
            assertFalse(r.store.canSendSticker(peer))
            assertFalse(r.store.sendDraft(peer, isComposing = false))
            assertFalse(r.store.sendSticker(AingSticker.joy, peer))
            assertEquals("안녕", r.store.draft(peer))
            assertNull(r.store.sendNotices[peer], "집중 사유를 결과 문구 자리에 적었다(풀린 뒤에도 남는다)")
        }
        advanceUntilIdle()
        assertEquals(0, r.sends())
        assertEquals(MessageNoticeText.senderFocused, MessagesFocusBlock.myself.notice)
        r.h.assertClean()
    }

    /** 모름(실패 · 행 없음 · 칸 null)은 막지 않는다 — 서버가 최종 판정. 기준선: 같은 조립에서 true 면 막힌다(위 시험). */
    @Test
    fun unknownMyFocusNeverBlocks() = runTest {
        for (reply in listOf(Reply.serverDown, Reply.Json("[]"), Reply.Json("""[{"focus_mode":null}]"""), Reply.Offline)) {
            val r = rig { it.received("a1", peerA, 0, unread = false) }
            r.focus.reply = reply
            r.store.appDidBecomeActive()
            r.store.conversationDidAppear(peerA, "t1")
            advanceUntilIdle()
            assertEquals(1, r.focusGets())
            assertNull(r.store.myFocusMode, "모름을 값으로 읽었다: $reply")
            r.store.setDraft("안녕", peerA)
            assertTrue(r.store.canSend(peerA), "모름이 보내기를 막았다: $reply")
            assertNull(r.store.focusBlock(peerA))
            r.h.assertClean()
        }
    }

    /** 실패는 알던 값을 바꾸지 않는다(켜짐을 알다가 GET 이 실패해도 켜짐 그대로 — 꺼짐으로 읽으면 막아야 할 전송이 열린다). */
    @Test
    fun failedRecheckKeepsTheKnownValue() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.focus.reply = Reply.Json("""[{"focus_mode":true}]""")
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(true, r.store.myFocusMode)
        r.focus.reply = Reply.serverDown
        r.store.refreshMyFocusModeIfFocused()
        advanceUntilIdle()
        assertEquals(2, r.focusGets())
        assertEquals(true, r.store.myFocusMode)
        r.h.assertClean()
    }

    /** 묻는 때: 대화가 설 때 · 대화가 떠 있는 채 앞으로 올 때. 목록만 · 대화 없이 앞으로 올 때는 묻지 않는다. 날아가는 중이면 겹쳐 띄우지 않는다. */
    @Test
    fun asksOnlyWhenAConversationStandsOrComesForwardOpen() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.store.appDidBecomeActive()
        r.store.listDidAppear()
        advanceUntilIdle()
        assertEquals(0, r.focusGets(), "대화가 없는데 내 집중을 물었다")
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(1, r.focusGets())
        // 대화가 떠 있는 채 뒤로 갔다 앞으로 — 한 번 더(맥에서 끄고 돌아오는 길).
        r.store.appDidEnterBackground()
        r.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, r.focusGets())
        // 대화를 닫고 앞으로 — 묻지 않는다.
        r.store.conversationDidDisappear("t1")
        r.store.appDidEnterBackground()
        r.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, r.focusGets(), "대화가 없는 앞으로 오기에 물었다")
        // 겹침: 응답을 붙잡은 채 두 번 서도 한 건.
        r.focus.gate = CompletableDeferred()
        r.store.conversationDidAppear(peerA, "t2")
        r.store.conversationDidAppear(peerB, "t3")
        runCurrent()
        assertTrue(r.store.isFetchingMyFocusMode)
        r.focus.gate!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(3, r.focusGets(), "날아가는 조회를 겹쳐 띄웠다")
        assertFalse(r.store.isFetchingMyFocusMode)
        r.h.assertClean()
    }

    /**
     * 지금 탭 60초 틱(폰 조립이 잇는 onPeriodicTick): 켜짐으로 알고 대화가 떠 있을 때만 다시 묻는다 — 맥에서 끈 집중을 따라잡는다.
     * 기준선: 꺼짐을 알 때 · 대화가 없을 때는 틱이 돌아도 묻지 않는다.
     */
    @Test
    fun nowTabTickRechecksOnlyWhileKnownOnAndConversationOpen() = runTest {
        val r = rig(withNow = true) { it.received("a1", peerA, 0, unread = false) }
        val now = r.now!!
        val scheduler = r.scheduler!!
        r.focus.reply = Reply.Json("""[{"focus_mode":false}]""")
        now.appDidBecomeActive()
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(1, r.focusGets())
        val refreshes = now.refreshCount
        scheduler.advance(60.0)
        advanceUntilIdle()
        assertEquals(refreshes + 1, now.refreshCount, "60초 틱이 돌지 않았다")
        assertEquals(1, r.focusGets(), "꺼짐을 아는데 틱이 물었다")
        // 서버 거절로 켜짐을 알게 됐다 → 틱마다 묻고, 맥에서 껐으면 풀린다.
        r.server.sendReply = Reply.Json(senderFocusedReply)
        r.store.setDraft("안녕", peerA)
        r.store.sendDraft(peerA, isComposing = false)
        advanceUntilIdle()
        assertEquals(true, r.store.myFocusMode)
        r.focus.reply = Reply.Json("""[{"focus_mode":true}]""")
        scheduler.advance(60.0)
        advanceUntilIdle()
        assertEquals(2, r.focusGets())
        assertEquals(true, r.store.myFocusMode)
        r.focus.reply = Reply.Json("""[{"focus_mode":false}]""")
        scheduler.advance(60.0)
        advanceUntilIdle()
        assertEquals(3, r.focusGets())
        assertEquals(false, r.store.myFocusMode, "맥에서 끈 집중을 틱이 따라잡지 못했다")
        r.server.sendReply = Reply.Json("""{"status":"ok"}""")
        assertTrue(r.store.canSend(peerA))
        // 켜짐이어도 대화가 없으면 묻지 않는다.
        r.server.sendReply = Reply.Json(senderFocusedReply)
        r.store.sendDraft(peerA, isComposing = false)
        advanceUntilIdle()
        assertEquals(true, r.store.myFocusMode)
        r.store.conversationDidDisappear("t1")
        scheduler.advance(60.0)
        advanceUntilIdle()
        assertEquals(3, r.focusGets(), "대화가 없는데 틱이 물었다")
        r.h.assertClean()
    }

    /** 계정 경계: 로그아웃(reset)이면 null · 세대가 바뀐 뒤 도착한 옛 응답은 버린다 · sender_focused 보다 먼저 띄운 조회의 답도 버린다. */
    @Test
    fun accountBoundaryAndLateAnswersAreDropped() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.focus.reply = Reply.Json("""[{"focus_mode":true}]""")
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(true, r.store.myFocusMode)
        r.store.reset()
        assertNull(r.store.myFocusMode, "로그아웃 뒤에도 앞 사람의 집중이 남았다")
        // 늦은 응답: 문에 붙잡은 조회(켜짐) → 다른 사람으로 로그인 → 문이 열린다 → 다음 계정은 모름 그대로.
        r.focus.gate = CompletableDeferred()
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t2")
        runCurrent()
        r.h.signInAs("11111111-0000-4000-8000-000000000002", idle = false)
        r.store.reset()
        r.focus.gate!!.complete(Unit)
        advanceUntilIdle()
        assertNull(r.store.myFocusMode, "로그아웃 전에 띄운 조회가 다음 계정을 잠갔다")
        r.h.assertClean()
    }

    @Test
    fun answerLaunchedBeforeSenderFocusedCannotUnlock() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.focus.reply = Reply.Json("""[{"focus_mode":false}]""")
        r.focus.gate = CompletableDeferred()
        r.server.sendReply = Reply.Json(senderFocusedReply)
        r.store.appDidBecomeActive()
        r.store.conversationDidAppear(peerA, "t1")
        runCurrent()
        assertTrue(r.store.isFetchingMyFocusMode)
        // 조회가 붙잡혀 있는 동안 서버가 보내기를 내 집중으로 거절했다(그 사이 맥에서 켰다).
        // ★ 문이 닫힌 동안 가상 시간을 밀지 않는다(advanceUntilIdle 이면 붙잡힌 조회가 HTTP 시한에 걸려 실패로 끝나 이 시험이 아무것도 못 잰다).
        r.store.setDraft("안녕", peerA)
        r.store.sendDraft(peerA, isComposing = false)
        runCurrent()
        assertEquals(1, r.sends())
        assertEquals(true, r.store.myFocusMode)
        assertTrue(r.store.isFetchingMyFocusMode, "붙잡은 조회가 이미 끝났다 — 이 시험의 전제가 무너졌다")
        r.focus.gate!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, r.focusGets(), "조회는 한 건이다")
        assertFalse(r.store.isFetchingMyFocusMode)
        assertEquals(true, r.store.myFocusMode, "거절보다 먼저 띄운 조회(꺼짐)가 켜짐을 덮었다")
        r.h.assertClean()
    }

    // ---------------------------------------------------------------- 3. 상대 집중

    /** 서버 실출력 8칸: 켠 사람만 잠기고 같은 문장 · 요청 0 · 글은 남는다. 같은 판의 끈 사람은 열려 있다(기준선). */
    @Test
    fun peerFocusFromServerDirectoryLocksOnlyThatPerson() = runTest {
        val r = rig()
        r.server.directory = directory8
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        r.store.conversationDidAppear(focusedInFixture, "t1")
        advanceUntilIdle()
        assertTrue(r.store.isPeerFocused(focusedInFixture))
        assertFalse(r.store.isPeerFocused(notFocusedInFixture))
        r.store.setDraft("안녕", focusedInFixture)
        assertEquals(MessagesFocusBlock.peer, r.store.focusBlock(focusedInFixture))
        assertFalse(r.store.canSend(focusedInFixture))
        assertFalse(r.store.canSendSticker(focusedInFixture))
        assertFalse(r.store.sendDraft(focusedInFixture, isComposing = false))
        assertFalse(r.store.sendSticker(AingSticker.joy, focusedInFixture))
        advanceUntilIdle()
        assertEquals(0, r.sends())
        assertEquals("안녕", r.store.draft(focusedInFixture))
        // 미리 막을 때와 서버가 거절할 때 같은 문장.
        assertEquals(MessageNoticeText.targetFocused, MessagesComposerRules.noticeLine(r.store.focusBlock(focusedInFixture), null))
        assertEquals(MessageNoticeText.targetFocused, MessagesSendRules.notice(com.yehsung.aingcheck.core.wire.models.MessageSendOutcome.TargetFocused, null))
        // 대화는 열린다(막히는 것은 보내기뿐) — 대화 화면이 선 기록이 있다.
        assertEquals(focusedInFixture, r.store.openConversationPeerID)
        r.store.setDraft("안녕", notFocusedInFixture)
        assertTrue(r.store.canSend(notFocusedInFixture))
        assertNull(r.store.focusBlock(notFocusedInFixture))
        // 판에도 같은 값(이름표 칩 · 사람 줄 칩의 재료).
        assertEquals(setOf(focusedInFixture), r.store.presenceBoard(r.h.now()).focused)
        r.h.assertClean()
    }

    /** 옛 서버(7칸 — 칸 없음)는 아무도 잠그지 않는다. */
    @Test
    fun oldServerWithoutTheColumnLocksNobody() = runTest {
        val r = rig()
        r.server.directory = directory7
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        advanceUntilIdle()
        assertTrue(r.store.directory.isNotEmpty())
        for (entry in r.store.directory) {
            r.store.setDraft("안녕", entry.userID)
            assertFalse(r.store.isPeerFocused(entry.userID), "칸이 없는 서버에서 ${entry.name} 이 잠겼다")
            assertTrue(r.store.canSend(entry.userID))
        }
        assertEquals(emptySet(), r.store.presenceBoard(r.h.now()).focused)
        r.h.assertClean()
    }

    /** 내 집중이 상대 집중보다 앞선다(서버 조각 순서) — 둘 다면 내 사유. */
    @Test
    fun myFocusWinsOverPeerFocus() = runTest {
        val r = rig()
        r.server.directory = directory8
        r.focus.reply = Reply.Json("""[{"focus_mode":true}]""")
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        r.store.conversationDidAppear(focusedInFixture, "t1")
        advanceUntilIdle()
        assertEquals(MessagesFocusBlock.myself, r.store.focusBlock(focusedInFixture))
        assertEquals(MessageNoticeText.senderFocused, MessagesComposerRules.noticeLine(r.store.focusBlock(focusedInFixture), "보냈어요"))
        assertEquals(MessagesFocusBlock.myself, MessagesFocusRules.block(true, peerFocused = true))
        assertEquals(MessagesFocusBlock.peer, MessagesFocusRules.block(false, peerFocused = true))
        assertEquals(MessagesFocusBlock.peer, MessagesFocusRules.block(null, peerFocused = true))
        assertNull(MessagesFocusRules.block(null, peerFocused = false))
        assertNull(MessagesFocusRules.block(false, peerFocused = false))
        r.h.assertClean()
    }

    /**
     * target_focused 를 받으면 상대를 로컬에서 찍지 않고 **명부 둘**(메시지 + 지금 탭)을 다시 받는다 — 판의 겹치기에서 지금 탭 명부가 이기기 때문이다.
     * 받은 명부가 집중이라 말하면 칩·잠금이 따라온다.
     */
    @Test
    fun targetFocusedRefetchesBothDirectoriesAndNeverMarksLocally() = runTest {
        val r = rig(withNow = true) { it.received("a1", focusedInFixture, 0, unread = false) }
        val now = r.now!!
        r.server.directory = directory7
        now.appDidBecomeActive()
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        r.store.conversationDidAppear(focusedInFixture, "t1")
        advanceUntilIdle()
        assertFalse(r.store.isPeerFocused(focusedInFixture))
        val directoryCalls = r.h.count("app_user_directory")
        val nowRefreshes = now.refreshCount
        // 그 사이 상대가 집중을 켰다 — 서버가 거절하고, 명부도 이제 8칸에서 켜짐을 말한다.
        r.server.sendReply = Reply.Json("""{"status":"target_focused"}""")
        r.server.directory = directory8
        r.store.setDraft("안녕", focusedInFixture)
        assertTrue(r.store.sendDraft(focusedInFixture, isComposing = false))
        advanceUntilIdle()
        assertEquals(MessageNoticeText.targetFocused, r.store.sendNotices[focusedInFixture])
        assertEquals("안녕", r.store.draft(focusedInFixture))
        assertEquals(directoryCalls + 2, r.h.count("app_user_directory"), "명부 둘을 다시 받지 않았다")
        assertEquals(nowRefreshes + 1, now.refreshCount, "지금 탭 명부를 다시 받지 않았다")
        assertTrue(r.store.isPeerFocused(focusedInFixture), "다시 받은 명부를 따라오지 않았다")
        assertEquals(MessagesFocusBlock.peer, r.store.focusBlock(focusedInFixture))
        r.h.assertClean()
    }

    @Test
    fun targetFocusedDoesNotLockWhenTheDirectoriesSayOtherwise() = runTest {
        val r = rig { it.received("a1", peerA, 0, unread = false) }
        r.server.directory = directory7
        r.server.sendReply = Reply.Json("""{"status":"target_focused"}""")
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        r.store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        r.store.setDraft("안녕", peerA)
        r.store.sendDraft(peerA, isComposing = false)
        advanceUntilIdle()
        assertFalse(r.store.isPeerFocused(peerA), "서버 거절 하나로 상대를 로컬에서 집중으로 찍었다")
        assertTrue(r.store.sendDraft(peerA, isComposing = false), "명부가 아니라는데 다음 누름을 막았다")
        advanceUntilIdle()
        assertEquals(2, r.sends())
        r.h.assertClean()
    }

    /** 겹치기 규칙(순수): 목록에 있는 사람은 그 목록의 값이 답 — 지금 탭(더 새 값)이 메시지 명부를 덮는다. 칸 없음 = 집중 아님. 나는 넣지 않는다. */
    @Test
    fun focusedOverlayFollowsTheNewerList() {
        val me = "me"
        fun entry(id: String, focused: Boolean) = PokeDirectoryEntry(id, id, null, isWorking = true, isFocused = focused)
        fun row(id: String, focus: Boolean?) = PokeDirectoryRow(id, id, null, isWorking = true, focusMode = focus)
        val messages = listOf(entry("a", true), entry("b", true), entry("c", false), entry(me, true))
        assertEquals(setOf("a", "b"), MessagesFocusRules.focusedPeerIDs(null, messages, me))
        // 지금 탭이 a 는 꺼짐 · b 는 칸 없음 · c 는 켜짐이라 말한다 — 지금 탭이 이긴다.
        val now = listOf(row("a", false), row("b", null), row("c", true), row(me, true))
        assertEquals(setOf("c"), MessagesFocusRules.focusedPeerIDs(now, messages, me))
        // 지금 탭에 없는 사람은 메시지 명부 값이 남는다.
        assertEquals(setOf("a", "b", "c"), MessagesFocusRules.focusedPeerIDs(listOf(row("c", true)), messages, me))
        assertEquals(emptySet(), MessagesFocusRules.focusedPeerIDs(null, null, me))
        // 틱 조건.
        assertTrue(MessagesFocusRules.rechecksOnTick(true, conversationOpen = true))
        assertFalse(MessagesFocusRules.rechecksOnTick(true, conversationOpen = false))
        assertFalse(MessagesFocusRules.rechecksOnTick(false, conversationOpen = true))
        assertFalse(MessagesFocusRules.rechecksOnTick(null, conversationOpen = true))
        // 입력줄 한 줄: 집중 사유가 결과 문구보다 앞 · 빈 결과는 없음.
        assertEquals(MessageNoticeText.targetFocused, MessagesComposerRules.noticeLine(MessagesFocusBlock.peer, "연결이 불안정해요"))
        assertEquals("연결이 불안정해요", MessagesComposerRules.noticeLine(null, "연결이 불안정해요"))
        assertNull(MessagesComposerRules.noticeLine(null, ""))
        assertNull(MessagesComposerRules.noticeLine(null, null))
    }

    /** 차단해 숨긴 사람은 판의 집중 집합에서도 빠진다(다른 칸과 같은 관문). */
    @Test
    fun blockedPeerLeavesTheFocusedSet() = runTest {
        val r = rig()
        r.server.directory = directory8
        r.server.blockReply = Reply.Json("null")
        r.store.appDidBecomeActive()
        r.store.loadDirectory(force = true)
        advanceUntilIdle()
        assertEquals(setOf(focusedInFixture), r.store.presenceBoard(r.h.now()).focused)
        r.store.blockPeer(focusedInFixture)
        // 숨김은 낙관적이다 — 서버 답을 기다리지 않고 판에서 빠진다.
        assertEquals(emptySet(), r.store.presenceBoard(r.h.now()).focused)
        advanceUntilIdle()
        r.h.assertClean()
    }

    // ---------------------------------------------------------------- 4. 확성기는 그대로(대표 답 "찌르기·메시지만")

    @Test
    fun megaphoneStillGoesOutWhileMyFocusIsOn() = runTest {
        val server = MessagesServer().also { it.received("a1", peerA, 0, unread = false) }
        val focus = FocusServer().also { it.reply = Reply.Json("""[{"focus_mode":true}]""") }
        val h = StoreHarness(this) { r ->
            focus.route(r) ?: server.route(r) ?: when (r.rpcName) {
                "megaphone_info" -> Reply.Json(
                    """{"status":"ok","enabled":true,"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":9,"max_length":200,"ruby_balance":120}""",
                )
                "send_megaphone" -> Reply.Json("""{"status":"ok","duplicate":false,"megaphone_id":"m1","recipients":9,"price":50,"ruby_balance":70}""")
                else -> null
            }
        }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, megaphoneHost = TestMegaphoneHost(h.session), focusSendGate = true)
        store.megaphone.makeRequestID = { "req-1" }
        store.appDidBecomeActive()
        store.conversationDidAppear(peerA, "t1")
        advanceUntilIdle()
        assertEquals(true, store.myFocusMode)
        assertEquals(MessagesFocusBlock.myself, store.focusBlock(peerA), "기준선: 같은 순간 1:1 메시지는 막혀 있다")
        val mega = store.megaphone
        mega.open()
        advanceUntilIdle()
        mega.setDraft("모두 안녕")
        mega.requestSend()
        assertTrue(mega.confirmSend())
        advanceUntilIdle()
        assertEquals(1, h.count("send_megaphone"), "내 집중이 확성기까지 막았다")
        h.assertClean()
    }

    private companion object {
        fun isMyFocusGet(r: RecordedRequest): Boolean =
            r.method == "GET" && r.path == "/rest/v1/profiles" && r.query.any { it.first == "select" && it.second == "focus_mode" }
    }
}
