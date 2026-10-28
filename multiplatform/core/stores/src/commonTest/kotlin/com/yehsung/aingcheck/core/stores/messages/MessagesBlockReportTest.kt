// 원본: Tests/CheckMobileKitTests/MessagesBlockReportTests.swift:150-408(차단 · 해제 · 신고 · 차단 목록 · 서버 미준비 · 로그아웃) @ 1b8260d
// 문구 기대값은 Swift 코어 원문(BlockReportRules.swift:93-205) 글자 그대로다.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesBlockReportTest {
    private val peerA = "peer-a"
    private val peerB = "peer-b"

    /** 두 사람의 대화가 있는 하네스(목록이 선 상태). Swift `MessagesBlockReportTests.make`. */
    private suspend fun TestScope.make(setup: (MessagesServer) -> Unit = {}): Triple<StoreHarness, MessagesServer, MessagesStore> {
        val server = MessagesServer().apply {
            received("a1", peerA, 0, name = "소라")
            received("a2", peerA, 10, name = "소라")
            received("b1", peerB, 20, name = "도윤")
            summary = """{"status":"ok","total":3,"peers":[{"peer_user_id":"peer-a","count":2,"last_epoch_ms":1},{"peer_user_id":"peer-b","count":1,"last_epoch_ms":1}]}"""
            directory = """[{"user_id":"peer-a","display_name":"소라","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"},""" +
                """{"user_id":"peer-b","display_name":"도윤","avatar_url":null,"is_working":false,"message_capable":true,"center":"busan"}]"""
            setup(this)
        }
        val h = StoreHarness(this) { server.route(it) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        return Triple(h, server, store)
    }

    private fun bodies(h: StoreHarness, rpc: String): List<String> = h.storeRequests.filter { it.rpcName == rpc }.map { it.bodyText }

    @Test
    fun blockHidesOptimisticallyEverywhereThenSendsOnce() = runTest {
        val (h, _, store) = make { it.blockReply = Reply.Json("null") }
        store.loadDirectory(force = true)
        advanceUntilIdle()
        assertEquals(setOf(peerA, peerB), store.threads.map { it.peerUserID }.toSet())
        assertEquals(3, store.badgeCount)
        // 대조: 차단 전에는 묶음·사람 찾기에 있다(아래 단언이 늘 참인 채로 초록이 되지 않게).
        assertTrue(store.filteredDirectory("").map { it.userID }.contains(peerA))

        store.blockPeer(peerA)
        // 응답 전에 이미 사라졌다 — 묶음 · 배지 · 점 · 사람 찾기 넷 다.
        assertEquals(listOf(peerB), store.threads.map { it.peerUserID })
        assertEquals(1, store.badgeCount)
        assertFalse(peerA in store.unreadPeerIDs)
        assertEquals(listOf(peerB), store.filteredDirectory("").map { it.userID })
        assertTrue(store.isHiddenByBlock(peerA))
        assertEquals(peerA, store.blockingPeerID)

        advanceUntilIdle()
        assertNull(store.blockingPeerID)
        assertEquals(listOf("""{"p_user":"peer-a"}"""), bodies(h, "block_user"), "차단 요청 본문이 계약과 다르다")
        assertNull(store.blockNotice, "성공했는데 문구가 섰다")
        assertEquals(listOf(peerB), store.threads.map { it.peerUserID })
        assertTrue(store.isHiddenByBlock(peerA), "성공했는데 숨김이 풀렸다")
        h.assertClean()
    }

    @Test
    fun blockFailureRestoresConversationWithReasonAndPullClearsIt() = runTest {
        val (h, _, store) = make { it.blockReply = Reply.Json("""{"message":"boom"}""", 500) }
        store.blockPeer(peerA)
        assertEquals(listOf(peerB), store.threads.map { it.peerUserID })
        advanceUntilIdle()
        assertNull(store.blockingPeerID)
        assertFalse(store.isHiddenByBlock(peerA), "실패했는데 대화가 사라진 채다")
        assertEquals(2, store.threads.size)
        assertEquals(3, store.badgeCount)
        assertEquals("차단하지 못했어요 — 연결을 확인하고 다시 시도해 주세요", store.blockNotice)
        assertTrue(store.blockNoticeIsError)
        store.refreshNow()
        assertNull(store.blockNotice)
        h.assertClean()
    }

    @Test
    fun serverNotReadySaysNotYetForBlockAndBlockList() = runTest {
        val (h, _, store) = make {
            it.missing += "block_user"
            it.missing += "list_blocks"
        }
        store.blockPeer(peerA)
        advanceUntilIdle()
        assertFalse(store.isHiddenByBlock(peerA))
        assertEquals("이 기능이 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요", store.blockNotice)

        store.blockedListDidAppear()
        advanceUntilIdle()
        assertTrue(store.blocksLoaded, "서버 미준비를 '불러오는 중'으로 남겼다")
        assertTrue(store.blocksServerNotReady)
        assertFalse(store.blocksFailed, "'아직' 을 '고장' 으로 말한다")
        assertEquals(emptyList(), store.blockedPeople)
        h.assertClean()
    }

    /** 대조(V18 기준선): 함수가 있는데 5xx 면 그건 '아직'이 아니라 실패다. */
    @Test
    fun blockListOutageIsAFailureNotNotYet() = runTest {
        val (h, _, store) = make { it.listBlocksReply = Reply.serverDown }
        store.blockedListDidAppear()
        advanceUntilIdle()
        assertTrue(store.blocksFailed)
        assertFalse(store.blocksLoaded)
        assertFalse(store.blocksServerNotReady)
        h.assertClean()
    }

    @Test
    fun reportGuardsAndPayloadAndAlsoBlockHides() = runTest {
        val (h, _, store) = make { it.reportReply = Reply.Json("null") }
        // ① 사유 미선택 — 왕복 0.
        var sent = store.submitReport(peerA, reason = null, detail = "", messageID = null, alsoBlock = true)
        assertFalse(sent)
        assertEquals("사유를 골라 주세요", store.reportNotice)
        assertEquals(0, h.count("report_content"))
        // ② 200자 초과 — 왕복 0.
        sent = store.submitReport(peerA, ContentReportReason.harassment, "가".repeat(201), null, alsoBlock = true)
        assertFalse(sent)
        assertEquals("자세한 내용은 200자까지예요", store.reportNotice)
        assertEquals(0, h.count("report_content"))
        // ③ 메시지 한 건 신고 + 같이 차단.
        assertFalse(store.isHiddenByBlock(peerA), "대조: 신고 전에는 보인다")
        sent = store.submitReport(peerA, ContentReportReason.harassment, "  욕을 했어요 ", "a2", alsoBlock = true)
        assertTrue(sent)
        assertEquals(1, h.count("report_content"))
        val body = bodies(h, "report_content").single()
        for (piece in listOf(""""p_target":"peer-a"""", """"p_reason":"harassment"""", """"p_detail":"욕을 했어요"""", """"p_message_id":"a2"""", """"p_block":true""")) {
            assertTrue(piece in body, "신고 본문에 $piece 가 없다: $body")
        }
        assertTrue(store.isHiddenByBlock(peerA), "차단까지 켜고 보냈는데 화면에 남아 있다")
        assertEquals(listOf(peerB), store.threads.map { it.peerUserID })
        assertEquals("신고를 접수했어요 · 24시간 안에 확인할게요", store.blockNotice)
        assertFalse(store.blockNoticeIsError)
        assertFalse(store.blocksLoaded, "차단 목록은 다음에 다시 받는다")
        h.assertClean()
    }

    @Test
    fun reportWithoutOptionalsSendsNullKeysNotMissingOnes() = runTest {
        val (h, _, store) = make { it.reportReply = Reply.Json("null") }
        val sent = store.submitReport(peerA, ContentReportReason.spam, "   ", null, alsoBlock = false)
        assertTrue(sent)
        val body = bodies(h, "report_content").single()
        for (piece in listOf(""""p_target":"peer-a"""", """"p_reason":"spam"""", """"p_detail":null""", """"p_message_id":null""", """"p_block":false""")) {
            assertTrue(piece in body, "신고 본문에 $piece 가 없다: $body")
        }
        assertFalse(store.isHiddenByBlock(peerA), "차단을 끄고 신고했는데 대화가 사라졌다")
        h.assertClean()
    }

    @Test
    fun reportFailureKeepsSheetAndDoesNotBlock() = runTest {
        val (h, _, store) = make { it.reportReply = Reply.Offline }
        val sent = store.submitReport(peerA, ContentReportReason.spam, "광고예요", null, alsoBlock = true)
        assertFalse(sent, "실패했는데 시트를 닫으라고 했다")
        assertEquals("신고를 보내지 못했어요 — 연결을 확인하고 다시 시도해 주세요", store.reportNotice)
        assertFalse(store.isHiddenByBlock(peerA))
        assertFalse(store.isSendingReport)
        store.reportSheetDidDisappear()
        assertNull(store.reportNotice)
        h.assertClean()
    }

    @Test
    fun blockedListShowsRowsAndUnblockRestoresConversation() = runTest {
        val (h, _, store) = make {
            it.blockReply = Reply.Json("null")
            it.unblockReply = Reply.Json("null")
            it.listBlocksReply = Reply.Json("""[{"user_id":"peer-a","display_name":"소라","avatar_url":null,"created_epoch":1789621000}]""")
        }
        store.blockPeer(peerA)
        advanceUntilIdle()
        assertTrue(store.isHiddenByBlock(peerA))
        store.blockedListDidAppear()
        advanceUntilIdle()
        assertEquals(listOf(peerA), store.blockedPeople.map { it.userID })
        assertEquals("소라", store.blockedPeople.first().name)
        assertNotNull(store.blockedPeople.first().blockedAt)
        assertFalse(store.blocksServerNotReady)

        val historyBefore = h.count("message_history_with_pokes")
        store.unblock(peerA)
        assertEquals(setOf(peerA), store.unblockingUserIDs)
        advanceUntilIdle()
        assertEquals(emptySet(), store.unblockingUserIDs)
        assertEquals(listOf("""{"p_user":"peer-a"}"""), bodies(h, "unblock_user"))
        assertEquals(emptyList(), store.blockedPeople)
        assertFalse(store.isHiddenByBlock(peerA), "차단을 풀었는데 대화가 계속 숨어 있다")
        assertEquals(2, store.threads.size, "차단을 풀었는데 대화가 돌아오지 않았다")
        assertTrue(h.count("message_history_with_pokes") > historyBefore, "해제 뒤 이력을 다시 받지 않았다")
        h.assertClean()
    }

    @Test
    fun unblockFailureKeepsRowWithReason() = runTest {
        val (h, _, store) = make {
            it.blockReply = Reply.Json("null")
            it.unblockReply = Reply.Json("""{"message":"nope"}""", 400)
            it.listBlocksReply = Reply.Json("""[{"user_id":"peer-a","display_name":"소라","avatar_url":null}]""")
        }
        store.blockPeer(peerA)
        advanceUntilIdle()
        store.blockedListDidAppear()
        advanceUntilIdle()
        store.unblock(peerA)
        advanceUntilIdle()
        assertEquals(listOf(peerA), store.blockedPeople.map { it.userID })
        assertTrue(store.isHiddenByBlock(peerA))
        assertEquals("차단을 풀지 못했어요 — 잠시 뒤 다시 시도해 주세요", store.blockedListNotice)
        h.assertClean()
    }

    @Test
    fun signOutDoesNotLeakBlockStateToNextAccount() = runTest {
        val (h, _, store) = make {
            it.blockReply = Reply.Json("null")
            it.listBlocksReply = Reply.Json("""[{"user_id":"peer-a","display_name":"소라"}]""")
        }
        store.blockPeer(peerA)
        advanceUntilIdle()
        store.blockedListDidAppear()
        advanceUntilIdle()
        assertTrue(store.blockedPeople.isNotEmpty())
        h.session.signOut()
        store.reset()
        assertEquals(emptySet(), store.hiddenBlockedPeerIDs)
        assertEquals(emptyList(), store.blockedPeople)
        assertFalse(store.blocksLoaded)
        assertNull(store.blockNotice)
        h.assertClean()
    }
}
