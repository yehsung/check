// 원본: Tests/checkTests/MessageOlderHistoryTests.swift ②(요청 본문 · 커서 · 디코드 · 확성기 줄 · 사진 줄) @ main 341eb4e3
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.messages.MessagePageCursor
import com.yehsung.aingcheck.core.wire.messages.MessagePageRequest
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 이전 대화 더 보기 전선(`message_page`, 맥 0.3.86 · 아이폰 1.0.19 와 한 계약). */
class V9MessagePageTest {
    private object TrimRules : WireTextRules {
        override fun sanitized(raw: String): String = raw.trim()
        override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
        override fun statusMessageSanitized(raw: String): String = raw.trim()
    }

    private val me = "11111111-1111-4111-8111-111111111111"
    private val peer = "22222222-2222-4222-8222-222222222222"
    private val other = "33333333-3333-4333-8333-333333333333"
    private val photoID = "44444444-4444-4444-8444-444444444444"

    private fun service(reply: String, bodies: MutableList<String> = mutableListOf()): SupabaseWorkService {
        val engine = MockEngine { request ->
            bodies += (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
            respond(reply, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
        }
        val client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) }
        return SupabaseWorkService("https://golden.invalid", "k", client, { SwiftDate(1_789_621_500.0) }, TrimRules) { "ABCDEF12-0000-4000-8000-000000000000" }
    }

    private fun row(
        id: String, mine: Boolean, us: Long, body: String = "지난 이야기", megaphone: Boolean = false,
        from: String? = null, to: String? = null, photoOnly: Boolean = false, unread: Boolean? = null,
    ): String {
        val f = from ?: if (mine) me else peer
        val t = to ?: if (mine) peer else me
        val stored = if (photoOnly) "📷 사진" else body
        val photo = if (photoOnly) """"photo_path":"$peer/$photoID.jpg","photo_width":1600,"photo_height":1200""" else """"photo_path":null,"photo_width":null,"photo_height":null"""
        return """{"id":"$id","from_user":"$f","to_user":"$t","body":"$stored","caption":${if (photoOnly) "null" else "\"$stored\""},$photo,""" +
            """"is_megaphone":$megaphone,"is_mine":$mine,"created_epoch_ms":${us / 1000},"created_epoch_us":"$us","read_by_peer":${if (mine) "false" else "null"},""" +
            """"unread_for_me":${if (mine) "null" else (unread ?: false).toString()}}"""
    }

    @Test
    fun requestAlwaysCarriesFourKeysWithExplicitNullsAndExactMicros() {
        val first = SwiftJson.parse(SwiftJson.encode(MessagePageRequest.serializer(), MessagePageRequest(peer, null, 50))) as JsonObject
        assertEquals(setOf("p_peer", "p_before_us", "p_before_id", "p_limit"), first.keys, "커서가 없어도 네 키를 싣는다(키 집합으로 함수를 고른다)")
        assertEquals(JsonNull, first["p_before_us"])
        assertEquals(JsonNull, first["p_before_id"])
        val big = 1_789_621_499_123_457L // 2^53 너머 — 실수로 지나면 끝자리가 바뀐다
        val next = SwiftJson.parse(SwiftJson.encode(MessagePageRequest.serializer(), MessagePageRequest(peer, MessagePageCursor(big, "m-01"), 50))) as JsonObject
        assertEquals(big.toString(), next.getValue("p_before_us").jsonPrimitive.content, "µs 커서가 정수 그대로 가지 않는다")
        assertEquals("m-01", next.getValue("p_before_id").jsonPrimitive.content)
    }

    @Test
    fun pageDropsMegaphoneAndOtherThreadsButKeepsTheirCursorAndReverses() = runBlocking {
        val bodies = mutableListOf<String>()
        val rows = listOf(
            row("m-05", mine = true, us = 5_000_000_000_005L, body = "다섯"),
            row("m-04", mine = false, us = 4_000_000_000_004L, body = "넷", unread = true),
            row("m-03", mine = false, us = 3_000_000_000_003L, megaphone = true, body = "확성기"),
            row("m-02", mine = false, us = 2_000_000_000_002L, from = other, to = me, body = "다른 대화"),
            """{"id": 7}""", // 깨진 원소 — 그 원소만 버린다
            row("m-01", mine = false, us = 1_000_000_000_001L, photoOnly = true),
        )
        val svc = service("[" + rows.joinToString(",") + "]", bodies)
        val page = svc.fetchMessagePage("tok", peer, me, before = null, limit = 6, peerName = "민수")
        assertEquals(1, bodies.size)
        assertEquals(listOf("m-01", "m-04", "m-05"), page.entries.map { it.id }, "오래된 것 → 최신, 확성기 · 다른 대화 · 깨진 원소 빠짐")
        assertEquals(6, page.rowCount, "버린 줄 · 깨진 원소도 줄 수에 든다")
        assertEquals(MessagePageCursor(1_000_000_000_001L, "m-01"), page.oldestCursor)
        assertTrue(page.hasMore, "꽉 찬 쪽(6 = 상한)이면 더 있다")
        val received = page.entries.first { it.id == "m-04" }
        assertNull(received.isUnread, "지난 쪽은 안 읽음 재료가 아니다(unread_for_me 를 옮기지 않는다)")
        val photo = assertNotNull(page.entries.first { it.id == "m-01" }.photo, "사진 줄에 사진이 실리지 않았다")
        assertEquals(1600L, photo.width)
        assertEquals("", page.entries.first { it.id == "m-01" }.body, "사진만 보낸 줄은 글이 비어 있다(화면은 사진만 그린다)")
        assertEquals(false, page.entries.first { it.id == "m-05" }.readByPeer, "내가 보낸 말의 읽음은 싣는다")
        assertEquals("민수", received.peerName)
    }

    @Test
    fun shortPageEndsAndMegaphoneOnlyPageStillMovesTheCursor() {
        val svc = service("[]")
        val megaOnly = svc.messagePage("[" + row("m-09", mine = false, us = 9L, megaphone = true) + "]", peer, me, limit = 1)
        assertTrue(megaOnly.entries.isEmpty())
        assertEquals(MessagePageCursor(9L, "m-09"), megaOnly.oldestCursor, "확성기만 담긴 쪽에서도 커서가 된다(거기서 멈추지 않게)")
        assertTrue(megaOnly.hasMore)
        val short = svc.messagePage("[" + row("m-08", mine = true, us = 8L) + "]", peer, me, limit = 50)
        assertFalse(short.hasMore, "상한보다 적으면 끝이다")
    }

    @Test
    fun brokenPhotoFallsBackToText() {
        val svc = service("[]")
        val bad = """{"id":"p-1","from_user":"$peer","to_user":"$me","body":"📷 사진","caption":null,"photo_path":"../etc/passwd","photo_width":10,""" +
            """"photo_height":10,"is_megaphone":false,"is_mine":false,"created_epoch_ms":1000,"created_epoch_us":1000000}"""
        val page = svc.messagePage("[$bad]", peer, me, limit = 50)
        val entry = page.entries.single()
        assertNull(entry.photo, "서버 모양이 아닌 경로가 사진으로 실렸다")
        assertEquals("📷 사진", entry.body, "깨진 사진 줄은 대체 글로 그린다")
    }
}
