// 원본: Tests/CheckMobileKitTests/MessagesMegaphoneTests.swift @ 1b8260d — 2단 확인 · 요청 id 쥐기(C§4 #26) · 함수 없음 · 로그아웃 비움 · 루비 미러
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.wire.SupabaseSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 세션 스토어 + 루비 미러 한 칸(조립의 오목 호스트 자리). */
class TestMegaphoneHost(private val store: SessionStore) : MegaphoneHost {
    override val session: SupabaseSession? get() = store.session
    override val sessionGeneration: Int get() = store.sessionGeneration
    override val service: SupabaseWorkService get() = store.service
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = store.withSessionRetry(operation)
    override var rubyBalance: Long? = null
}

@OptIn(ExperimentalCoroutinesApi::class)
class MegaphoneStoreTest {
    private fun info(recipients: Int = 9, ruby: Long? = 120, cooldown: Int = 0): String =
        """{"status":"ok","enabled":true,"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":$cooldown,""" +
            """"recipients":$recipients,"max_length":200""" + (ruby?.let { ""","ruby_balance":$it}""" } ?: "}")

    private suspend fun TestScope.make(send: () -> Reply, infoBody: () -> String = { info() }): Triple<StoreHarness, MessagesStore, TestMegaphoneHost> {
        val h = StoreHarness(this) { r ->
            when (r.rpcName) {
                "megaphone_info" -> Reply.Json(infoBody())
                "send_megaphone" -> send()
                else -> null
            }
        }
        h.signIn()
        val host = TestMegaphoneHost(h.session)
        var ids = 0
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, megaphoneHost = host)
        store.megaphone.makeRequestID = { "req-${++ids}" }
        return Triple(h, store, host)
    }

    @Test
    fun twoStepConfirmSendsOnceAndMirrorsServerRuby() = runTest {
        var wallet = 120L
        val (h, store, host) = make(
            send = {
                wallet -= 50
                Reply.Json("""{"status":"ok","duplicate":false,"megaphone_id":"m1","recipients":9,"price":50,"ruby_balance":$wallet}""")
            },
            infoBody = { info(ruby = wallet) },
        )
        val mega = store.megaphone
        mega.open()
        advanceUntilIdle()
        assertEquals(120L, host.rubyBalance, "정보 응답의 잔량을 미러로")
        assertEquals("지금 보내면 9명에게 가요", mega.infoLine(h.now()))
        mega.setDraft("  모두 안녕  ")
        mega.requestSend()
        assertTrue(mega.isConfirming)
        assertEquals(0, h.count("send_megaphone"), "첫 [보내기] 가 요청을 냈다")
        assertEquals("루비 50개로 9명에게 보낼까요?", mega.confirmQuestion)
        assertTrue(mega.confirmSend())
        assertFalse(mega.confirmSend(), "확인 연타가 요청을 둘 냈다")
        advanceUntilIdle()
        assertEquals(1, h.count("send_megaphone"))
        assertEquals("""{"p_body":"모두 안녕","p_request_id":"req-1"}""", h.storeRequests.single { it.rpcName == "send_megaphone" }.bodyText)
        assertEquals("보냈어요 · 9명에게", mega.notice)
        assertEquals("", mega.draft)
        assertNull(mega.pendingRequestID, "서버가 답을 줬는데 id 를 쥐고 있다")
        assertEquals(70L, host.rubyBalance, "보낸 뒤 미러는 서버 값")
        h.assertClean()
    }

    /** C§4 #26: 결과를 모르는 실패면 **같은 id 를 쥔 채** 다시 묻는다(서버가 이미 처리했을 수 있다 — 두 번 깎이지 않게). */
    @Test
    fun unknownFailureKeepsRequestIDForTheRetry() = runTest {
        var attempts = 0
        val (h, store, _) = make(send = {
            attempts += 1
            if (attempts == 1) Reply.Offline else Reply.Json("""{"status":"ok","duplicate":true,"recipients":9,"price":50}""")
        })
        val mega = store.megaphone
        mega.open()
        advanceUntilIdle()
        mega.setDraft("안녕")
        mega.requestSend()
        mega.confirmSend()
        advanceUntilIdle()
        assertEquals("req-1", mega.pendingRequestID)
        assertTrue(mega.isConfirming, "결과를 모르면 확인 단계에 남는다")
        assertTrue(mega.noticeIsError)
        mega.confirmSend()
        advanceUntilIdle()
        val ids = h.storeRequests.filter { it.rpcName == "send_megaphone" }.map { it.bodyText.substringAfter("p_request_id\":\"").substringBefore('"') }
        assertEquals(listOf("req-1", "req-1"), ids, "다시 확인했는데 새 id 로 물었다")
        assertEquals("이미 보냈어요 · 9명에게", mega.notice)
        assertNull(mega.pendingRequestID)
        h.assertClean()
    }

    @Test
    fun missingFunctionLocksAndDropsID() = runTest {
        val (h, store, _) = make(send = { Reply.missingFunction })
        val mega = store.megaphone
        mega.open()
        advanceUntilIdle()
        mega.setDraft("안녕")
        mega.requestSend()
        mega.confirmSend()
        advanceUntilIdle()
        assertTrue(mega.serverUnavailable)
        assertNull(mega.pendingRequestID, "함수가 없으면 서버에서 아무것도 안 돌았다 — id 를 버린다")
        assertFalse(mega.isConfirming)
        assertFalse(mega.canRequestSend, "함수 없는 서버에서 버튼이 살아 있다")
        h.assertClean()
    }

    @Test
    fun signOutResetClearsDraftInfoAndID() = runTest {
        val (h, store, _) = make(send = { Reply.Offline })
        val mega = store.megaphone
        mega.open()
        advanceUntilIdle()
        mega.setDraft("앞 사람의 글")
        mega.requestSend()
        mega.confirmSend()
        advanceUntilIdle()
        assertEquals("req-1", mega.pendingRequestID)
        store.reset()
        assertEquals("", mega.draft)
        assertNull(mega.info)
        assertNull(mega.pendingRequestID, "다음 사람이 앞 사람의 id 로 묻는다")
        h.assertClean()
    }
}
