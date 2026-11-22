// 원본: Tests/CheckMobileKitTests/V1019MessagePhotoTests.swift @ 5b6ab3ac(폰 1.0.19 — 1:1 메시지 사진 · 맥 0.3.86 과 같은 코어 전선) — 판 9
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.net.signedObjectURL
import com.yehsung.aingcheck.core.stores.me.EncodedPhoto
import com.yehsung.aingcheck.core.stores.me.PhotoEncoding
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoLayout
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoSendOutcome
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoText
import com.yehsung.aingcheck.core.wire.messages.SendPhotoMessageRequest
import com.yehsung.aingcheck.core.wire.messages.SendPhotoMessageResponse
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 1:1 메시지 사진(대표 #d_xygj8oZRFlfH 4번 메시지 묶음). */
@OptIn(ExperimentalCoroutinesApi::class)
class V9MessagePhotoTest {
    private val peer = "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
    /** 사진 경로의 첫 폴더는 uuid 계정이다(서버 정책 auth.uid() · 와이어 MessagePhotoWire.isServerShaped). */
    private val me = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
    private val photoPrefix = "/storage/v1/object/message-photos/"

    /** 시험용 줄이기 — 첫 바이트가 'x' 면 못 읽는 그림, 아니면 64×48 JPEG 로 친다(실제 그림 도구는 androidApp 몫). */
    private val fakeEncoder = PhotoEncoding { data -> if (data.isEmpty() || data.first() == 'x'.code.toByte()) null else EncodedPhoto(data, 64, 48) }

    private fun photoRow(id: String, epochSeconds: Long, caption: String?): String {
        val path = "$peer/0f8fad5b-d9cb-469f-a165-70867728950e.jpg"
        val captionJSON = caption?.let { "\"$it\"" } ?: "null"
        return """{"id":"$id","from_user":"$peer","to_user":"$me","body":"📷 사진","caption":$captionJSON,"photo_path":"$path","photo_width":800,"photo_height":600,""" +
            """"is_megaphone":false,"is_mine":false,"created_epoch_ms":${epochSeconds * 1000},"created_epoch_us":${epochSeconds * 1_000_000},"read_by_peer":null,"unread_for_me":false}"""
    }

    private fun TestScope.photoStore(h: StoreHarness): MessagesStore {
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.photoEncoder = fakeEncoder
        store.photoComputeContext = StandardTestDispatcher(testScheduler)
        var n = 0
        store.newPhotoID = { "0f8fad5b-d9cb-469f-a165-00000000000${++n}" }
        return store
    }

    @Test
    fun wireShapesMatchTheContract() {
        // 여섯 키를 언제나 — 설명이 없으면 p_caption 은 JSON null.
        val body = SwiftJson.parse(SwiftJson.encode(SendPhotoMessageRequest.serializer(), SendPhotoMessageRequest(peer, "a/b.jpg", 64, 48, null, "k"))) as JsonObject
        assertEquals(listOf("p_to", "p_path", "p_width", "p_height", "p_caption", "p_client_message_id"), body.keys.toList())
        assertEquals(JsonNull, body["p_caption"])
        // 응답: 봉투 + 덤 칸 · 사진만의 셋.
        val ok = SwiftJson.decode(SendPhotoMessageResponse.serializer(), """{"status":"ok","message_id":"m1","photo_path":"$me/0f8fad5b-d9cb-469f-a165-70867728950e.jpg","photo_width":64,"photo_height":48}""")
        assertEquals("m1", ok.send.messageId)
        assertEquals(64L, ok.attachment?.width)
        // 칸 하나가 깨져도(글자로 온 폭) 응답 전체는 산다 — 사진 칸만 없다(Swift try? 와 같다).
        val broken = SwiftJson.decode(SendPhotoMessageResponse.serializer(), """{"status":"ok","message_id":"m2","photo_path":"$me/0f8fad5b-d9cb-469f-a165-70867728950e.jpg","photo_width":"64","photo_height":48}""")
        assertEquals("m2", broken.send.messageId)
        assertNull(broken.attachment)
        val door = SwiftJson.decode(SendPhotoMessageResponse.serializer(), """{"status":"unsupported_client","door_open":true}""")
        assertEquals(MessagePhotoSendOutcome.unsupportedClient(true), MessagePhotoSendOutcome.of(door))
        assertEquals(MessagePhotoSendOutcome.photoMissing, MessagePhotoSendOutcome.of(SwiftJson.decode(SendPhotoMessageResponse.serializer(), """{"status":"photo_missing","door_open":"깨짐"}""")))
        // 서명 URL: 상대 경로면 프로젝트 주소 + /storage/v1 · 절대 URL 은 그대로.
        assertEquals("https://p.example/storage/v1/object/sign/message-photos/a.jpg?token=t", signedObjectURL("""{"signedURL":"/object/sign/message-photos/a.jpg?token=t"}""".encodeToByteArray(), "https://p.example/"))
        assertEquals("https://cdn.example/x", signedObjectURL("""{"signedUrl":"https://cdn.example/x"}""".encodeToByteArray(), "https://p.example"))
        assertNull(signedObjectURL("""{"nope":1}""".encodeToByteArray(), "https://p.example"))
        // 말풍선: 비율 · 하한 60 · 폰 상한 220×260.
        assertEquals(220.0 to 165.0, MessagePhotoLayout.bubbleSize(800, 600, MessagePhotoLayout.phoneMaxWidth, MessagePhotoLayout.phoneMaxHeight))
        assertEquals(60.0 to 260.0, MessagePhotoLayout.bubbleSize(10, 4000, MessagePhotoLayout.phoneMaxWidth, MessagePhotoLayout.phoneMaxHeight))
    }

    @Test
    fun metaIsAskedOnOpenAndLaidOnHeadRowsOnlyWhenDrawn() = runTest {
        val server = MessagesServer()
        server.received("ph-1", peer, at = 10, body = "📷 사진")
        val base = server.base
        val h = StoreHarness(this) { r ->
            if (r.rpcName == "message_page") Reply.Json("[" + photoRow("ph-1", base + 10, "바다") + "]") else server.route(r)
        }
        h.signIn(me)
        val store = photoStore(h)
        store.listDidAppear()
        advanceUntilIdle()
        assertEquals(0, h.count("message_page"), "대화를 열기 전에 사진 칸을 물었다")
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        assertTrue(store.photoMetaIdle)
        assertEquals(true, store.photoMetaAvailable)
        val body = h.storeRequests.first { it.rpcName == "message_page" }.bodyText
        assertTrue(body.contains("\"p_limit\":30") && body.contains("\"p_before_us\":null"), body)
        assertEquals(1, h.count("message_page"), "대화를 열 때 한 번이어야 한다(머리 변화가 또 묻는다)")
        val shown = store.conversationMessages(peer).first { it.id == "ph-1" }
        assertEquals(800L, shown.wire.photo?.width)
        assertEquals("바다", shown.wire.body)
        assertNull(store.history.first { it.id == "ph-1" }.wire.photo, "24시간 머리를 바꿨다")
        store.conversationDidDisappear("t1")
        assertTrue(store.photoMeta.isEmpty())
        h.assertClean()
    }

    @Test
    fun windowsBuildWithoutEncoderNeverAsksForPhotoMeta() = runTest {
        val server = MessagesServer()
        server.received("ph-1", peer, at = 10, body = "📷 사진")
        val h = StoreHarness(this) { r -> if (r.rpcName == "message_page") Reply.Json("[]") else server.route(r) }
        h.signIn(me)
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        assertEquals(0, h.count("message_page"), "줄이기가 없는 조립(Windows v1)이 사진 칸을 물었다")
        assertFalse(store.showsPhotoButton(peer))
        h.assertClean()
    }

    @Test
    fun sendUploadsThenSendsWithTheSameKeyAndDrawsInPlace() = runTest {
        val server = MessagesServer()
        server.received("m-1", peer, at = 10)
        val h = StoreHarness(this) { r ->
            when {
                r.rpcName == "message_page" -> Reply.Json("[]")
                r.rpcName == "send_photo_message" -> Reply.Json("""{"status":"ok","body":"설명","ring":"sent","message_id":"sent-1","photo_path":null,"photo_width":null,"photo_height":null}""")
                r.method == "POST" && r.path.startsWith(photoPrefix) -> Reply.Json("""{"Key":"ok"}""")
                else -> server.route(r)
            }
        }
        h.signIn(me)
        val store = photoStore(h)
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        assertTrue(store.showsPhotoButton(peer) && store.canSendPhoto(peer))
        store.preparePhoto("jpeg".encodeToByteArray(), peer)
        advanceUntilIdle()
        val draft = assertNotNull(store.photoDraft(peer))
        assertEquals(draft.id.lowercase(), draft.id)
        assertEquals(64 to 48, draft.encoded.pixelWidth to draft.encoded.pixelHeight)
        store.setDraft("설명", peer)
        store.sendPhotoDraft(peer)
        advanceUntilIdle()
        assertFalse(store.isSending)
        val uploads = h.storeRequests.filter { it.path.startsWith(photoPrefix) }
        assertEquals(listOf("$photoPrefix$me/${draft.id}.jpg"), uploads.map { it.path })
        assertTrue(uploads.none { r -> r.headers.keys.any { it.equals("x-upsert", ignoreCase = true) } }, "같은 경로를 덮으면 안 된다")
        val sent = SwiftJson.parse(h.storeRequests.first { it.rpcName == "send_photo_message" }.bodyText) as JsonObject
        assertEquals(draft.id, sent["p_client_message_id"]!!.jsonPrimitive.content)
        assertEquals("설명", sent["p_caption"]!!.jsonPrimitive.content)
        assertEquals("$me/${draft.id}.jpg", sent["p_path"]!!.jsonPrimitive.content)
        assertEquals(64L, sent["p_width"]!!.jsonPrimitive.long)
        assertEquals(48L, sent["p_height"]!!.jsonPrimitive.long)
        assertNull(store.photoDraft(peer), "보낸 뒤 사진이 남았다")
        assertEquals("", store.draft(peer), "보낸 뒤 설명이 남았다")
        val meta = assertNotNull(store.photoMeta[peer]?.get("sent-1"))
        assertEquals("$me/${draft.id}.jpg", meta.attachment.path)
        assertEquals("설명", meta.caption)
        assertNotNull(store.photoImage(meta.attachment.path), "내 사진을 다시 받으려 한다")
        h.assertClean()
    }

    @Test
    fun ambiguousFailureRetriesOnceWithTheSameNameAndKey() = runTest {
        val server = MessagesServer()
        var sends = 0
        var uploads = 0
        val h = StoreHarness(this) { r ->
            when {
                r.rpcName == "message_page" -> Reply.Json("[]")
                r.rpcName == "send_photo_message" -> if (++sends == 1) Reply.Offline else Reply.Json("""{"status":"ok","message_id":"sent-1"}""")
                // 첫 올리기는 답을 못 받았고(실은 올라갔다) 두 번째는 409 — 우리 앞 시도의 우리 파일이다.
                r.method == "POST" && r.path.startsWith(photoPrefix) -> if (++uploads == 1) Reply.Offline else Reply.Json("""{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}""", 400)
                else -> server.route(r)
            }
        }
        h.signIn(me)
        val store = photoStore(h)
        store.sendRetryDelaySeconds = 0.1
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        store.preparePhoto("jpeg".encodeToByteArray(), peer)
        advanceUntilIdle()
        val id = assertNotNull(store.photoDraft(peer)).id
        store.sendPhotoDraft(peer)
        advanceUntilIdle()
        val paths = h.storeRequests.filter { it.path.startsWith(photoPrefix) }.map { it.path }.toSet()
        assertEquals(setOf("$photoPrefix$me/$id.jpg"), paths, "다시 올릴 때 이름이 바뀌었다")
        val keys = h.storeRequests.filter { it.rpcName == "send_photo_message" }.map { (SwiftJson.parse(it.bodyText) as JsonObject)["p_client_message_id"]!!.jsonPrimitive.content }
        assertEquals(listOf(id, id), keys, "다시 보낼 때 키가 바뀌었다")
        assertNull(store.photoDraft(peer))
        assertNull(store.sendNotices[peer])
        h.assertClean()
    }

    @Test
    fun doorClosedHidesTheButtonKeepsTheTextAndReopenRearms() = runTest {
        val server = MessagesServer()
        val h = StoreHarness(this) { r ->
            when {
                r.rpcName == "message_page" -> Reply.Json("[]")
                r.rpcName == "send_photo_message" -> Reply.Json("""{"status":"unsupported_client","door_open":false}""")
                r.method == "POST" && r.path.startsWith(photoPrefix) -> Reply.Json("""{"Key":"ok"}""")
                else -> server.route(r)
            }
        }
        h.signIn(me)
        val store = photoStore(h)
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        store.preparePhoto("jpeg".encodeToByteArray(), peer)
        advanceUntilIdle()
        store.setDraft("남을 글", peer)
        store.sendPhotoDraft(peer)
        advanceUntilIdle()
        assertTrue(store.photoSendClosed)
        assertFalse(store.showsPhotoButton(peer))
        assertNull(store.photoDraft(peer))
        assertEquals(MessagePhotoText.doorClosedNotice, store.sendNotices[peer])
        assertEquals("남을 글", store.draft(peer))
        store.conversationDidDisappear("t1")
        store.conversationDidAppear(peer, "t2")
        assertTrue(store.showsPhotoButton(peer), "대화를 다시 열었는데 [사진]이 숨은 채다")
        h.assertClean()
    }

    @Test
    fun unreadablePhotoSaysSoAndShowsNoPreview() = runTest {
        val server = MessagesServer()
        val h = StoreHarness(this) { r -> if (r.rpcName == "message_page") Reply.Json("[]") else server.route(r) }
        h.signIn(me)
        val store = photoStore(h)
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        store.preparePhoto("xnot an image".encodeToByteArray(), peer)
        advanceUntilIdle()
        assertFalse(store.photoPreparing)
        assertNull(store.photoDraft(peer))
        assertEquals(MessagePhotoText.unreadableNotice, store.sendNotices[peer])
        h.assertClean()
    }

    @Test
    fun receivedPhotoIsFetchedOnceAndFailureIsRememberedUntilRetry() = runTest {
        val server = MessagesServer()
        val h = StoreHarness(this) { r -> if (r.rpcName == "message_page") Reply.Json("[]") else server.route(r) }
        h.signIn(me)
        val store = photoStore(h)
        var calls = 0
        var fail = true
        store.photoDataLoader = { calls += 1; if (fail) error("끊김") else "img".encodeToByteArray() }
        val path = "$peer/0f8fad5b-d9cb-469f-a165-70867728950e.jpg"
        store.requestPhotoImage(path)
        store.requestPhotoImage(path)
        advanceUntilIdle()
        assertEquals(1, calls, "같은 경로를 두 번 받았다")
        assertEquals(MessagesPhotoLoadState.failed, store.photoLoadState(path))
        store.requestPhotoImage(path)
        advanceUntilIdle()
        assertEquals(1, calls, "실패를 기억하지 않고 또 받았다")
        fail = false
        store.retryPhotoImage(path)
        advanceUntilIdle()
        assertEquals(2, calls)
        assertNotNull(store.photoImage(path))
        // 서버 모양이 아닌 경로는 받지 않는다.
        store.requestPhotoImage("../etc/passwd")
        advanceUntilIdle()
        assertEquals(2, calls)
        h.assertClean()
    }
}
