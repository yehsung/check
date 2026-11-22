// 원본: Tests/CheckMobileKitTests/V1019FeedbackShotTests.swift @ 6a6141ce(폰 1.0.19 — 제보 화면 캡처 · 맥 0.3.86 과 같은 계약 v2 §3) — 판 9
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.PrivateStorageError
import com.yehsung.aingcheck.core.net.PrivateStorageOperation
import com.yehsung.aingcheck.core.net.privateStorageError
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.FeedbackShotRow
import com.yehsung.aingcheck.core.wire.models.FeedbackShotText
import com.yehsung.aingcheck.core.wire.models.FeedbackShotWire
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class V9FeedbackShotTest {
    private val reportID = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private val shotPrefix = "/storage/v1/object/feedback-shots/"

    /** 시험용 줄이기 — 바이트 첫 글자가 'x' 면 못 읽는 그림, 아니면 40×30 JPEG 로 친다(실제 그림 도구는 androidApp 몫). */
    private val fakeEncoder = PhotoEncoding { data -> if (data.firstOrNull() == 'x'.code.toByte()) null else EncodedPhoto(data, 40, 30) }
    private fun image(tag: String = "a") = "jpeg-$tag".encodeToByteArray()

    @Test
    fun tallyPicksTheSameLinesAsMacAndPhone() {
        val all = MeFeedbackShotTally(2).apply { record(MeFeedbackShotStep.attached); record(MeFeedbackShotStep.attached) }
        assertEquals(FeedbackText.sendSuccess, all.notice)
        val none = MeFeedbackShotTally(2).apply { record(MeFeedbackShotStep.failed); record(MeFeedbackShotStep.failed) }
        assertEquals(FeedbackShotText.sentShotsFailed, none.notice)
        val some = MeFeedbackShotTally(3).apply { record(MeFeedbackShotStep.attached); record(MeFeedbackShotStep.failed); record(MeFeedbackShotStep.attached) }
        assertEquals(FeedbackShotText.sentSomeShotsFailed(1), some.notice)
        val door = MeFeedbackShotTally(2).apply { record(MeFeedbackShotStep.doorClosed) }
        assertEquals(FeedbackShotText.sentShotsDoorClosed, door.notice)
        assertTrue(MeFeedbackShotStep.doorClosed.stops)
        val old = MeFeedbackShotTally(1).apply { record(MeFeedbackShotStep.outdated) }
        assertEquals(FeedbackShotText.sentShotsAppOutdated, old.notice)
        assertTrue(MeFeedbackShotStep.outdated.closesTheDoor)
        val many = MeFeedbackShotTally(1).apply { record(MeFeedbackShotStep.tooMany(3)) }
        assertEquals(FeedbackShotText.sentShotsTooMany(3), many.notice)
        assertFalse(MeFeedbackShotStep.failed.stops)
        assertTrue(MeFeedbackShotStep.refused.stops)
        // 문구는 맥 · 아이폰과 같은 글(숫자는 상수에서).
        assertEquals("캡처 2장", FeedbackShotText.chip(2))
        assertEquals("1/3", FeedbackShotText.attachedCount(1))
        assertEquals("캡처는 3장까지 붙일 수 있어요", FeedbackShotText.full)
    }

    @Test
    fun wireShapesMatchTheServerContract() {
        assertEquals("u-1/$reportID/abc.jpg", FeedbackShotWire.objectPath("U-1", reportID.uppercase(), "ABC"))
        assertEquals(reportID, FeedbackShotWire.reportID("  ${reportID.uppercase()} "))
        assertNull(FeedbackShotWire.reportID("not-a-uuid"))
        assertNull(FeedbackShotWire.reportID(null))
        assertNull(FeedbackShotWire.acceptedPath("../etc/passwd"))
        // 묶기: 쓸 수 없는 행은 버리고 · 시각 → id 순 · 상한까지만.
        val rows = (1..5).map { i -> FeedbackShotRow(reportID.uppercase(), "a$i", "u/$reportID/$i.jpg", 40, 30, (10 - i).toLong()) } +
            FeedbackShotRow(reportID, "bad", "u/$reportID/bad.jpg", 0, 30, 1) + FeedbackShotRow(reportID, "evil", "../x", 40, 30, 1)
        val grouped = FeedbackShotWire.grouped(rows)
        assertEquals(listOf("a5", "a4", "a3"), grouped[reportID]?.map { it.id })
        // 요청 본문: 네 키 · uuid[] 한 키.
        val attach = SwiftJson.encode(com.yehsung.aingcheck.core.wire.models.FeedbackAttachShotRequest.serializer(),
            com.yehsung.aingcheck.core.wire.models.FeedbackAttachShotRequest(reportID, "u/$reportID/1.jpg", 40, 30))
        assertEquals("""{"p_report":"$reportID","p_path":"u/$reportID/1.jpg","p_width":40,"p_height":30}""", attach)
    }

    @Test
    fun storageErrorsSplitIntoPlainWords() {
        fun e(code: Int, body: String, op: PrivateStorageOperation = PrivateStorageOperation.upload) = privateStorageError(code, body.encodeToByteArray(), op)
        assertEquals(PrivateStorageError.alreadyExists, e(400, """{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"""))
        assertEquals(PrivateStorageError.forbidden, e(400, """{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"""))
        assertEquals(SupabaseWorkServiceError.SessionExpired, e(400, """{"statusCode":"403","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"""))
        assertEquals(SupabaseWorkServiceError.DatabaseSchemaMissing, e(400, """{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}"""))
        assertEquals(SupabaseWorkServiceError.DatabaseSchemaMissing, e(404, """{"error":"not_found"}"""))
        assertEquals(PrivateStorageError.objectMissing, e(404, """{"error":"not_found"}""", PrivateStorageOperation.read))
        assertEquals(PrivateStorageError.tooLarge, e(413, """{"error":"Payload too large"}"""))
        assertTrue(e(503, "upstream") is SupabaseWorkServiceError.InvalidResponse)
    }

    @Test
    fun attachThenSendUploadsIntoTheReportFolderAfterTheText() = runTest {
        val h = MeHarness(this) { r ->
            when {
                r.rpcName == "submit_feedback" -> MeReply.Json("\"$reportID\"")
                r.rpcName == "feedback_attach_shot" -> MeReply.Json("""{"status":"ok","attachment_id":"a1","duplicate":false}""")
                r.rpcName == "feedback_list" -> MeReply.Json("""[{"id":"$reportID","user_id":"user-1","kind":"bug","body":"글","status":"open","created_at":"2026-09-17T01:00:00Z"}]""")
                r.rpcName == "feedback_reply_latest" -> MeReply.Json("null")
                r.rpcName == "feedback_shots" -> MeReply.Json("""[{"report_id":"$reportID","attachment_id":"a1","path":"user-1/$reportID/x.jpg","width":40,"height":30,"created_epoch_ms":1}]""")
                r.method == "POST" && r.path.startsWith(shotPrefix) -> MeReply.Json("""{"Key":"ok"}""")
                else -> null
            }
        }
        h.store.photoEncoder = fakeEncoder
        h.signIn()
        advanceUntilIdle()
        h.store.feedbackDidAppear()
        advanceUntilIdle()
        assertTrue(h.store.feedbackShotAttachShown)
        assertEquals(3, h.store.feedbackShotRoom)
        h.store.attachFeedbackShots(listOf(image("1"), image("2")))
        advanceUntilIdle()
        assertEquals(2, h.store.feedbackShots.size)
        assertFalse(h.store.feedbackShotPreparing)
        assertEquals(40 to 30, h.store.feedbackShots.first().let { it.pixelWidth to it.pixelHeight })

        h.store.feedbackDraft = "사진이 안 보여요"
        h.store.sendFeedback()
        advanceUntilIdle()
        assertEquals(FeedbackText.sendSuccess, h.store.feedbackNotice)
        assertTrue(h.store.feedbackShots.isEmpty(), "보낸 캡처가 다음 제보를 위해 남았다")
        val uploads = h.meRequests.filter { it.path.startsWith(shotPrefix) }
        assertEquals(2, uploads.size)
        assertTrue(uploads.all { it.path.contains("/user-1/$reportID/") && it.path.endsWith(".jpg") }, uploads.map { it.path }.toString())
        assertEquals(2, uploads.map { it.path }.toSet().size, "시도마다 새 uuid 경로여야 한다")
        assertTrue(uploads.none { r -> r.headers.keys.any { it.equals("x-upsert", ignoreCase = true) } }, "같은 경로를 덮으면 안 된다")
        val attaches = h.meRequests.filter { it.rpcName == "feedback_attach_shot" }
        assertEquals(2, attaches.size)
        val first = SwiftJson.parse(attaches.first().bodyText) as JsonObject
        assertEquals(reportID, (first["p_report"] as JsonPrimitive).content)
        assertEquals(40L, first["p_width"]!!.jsonPrimitive.long)
        assertEquals(30L, first["p_height"]!!.jsonPrimitive.long)
        // 순서: 글 → (올리기 → 붙이기)×2.
        val order = h.meRequests.mapNotNull { r ->
            when {
                r.rpcName == "submit_feedback" -> "submit"
                r.rpcName == "feedback_attach_shot" -> "attach"
                r.path.startsWith(shotPrefix) -> "upload"
                else -> null
            }
        }
        assertEquals(listOf("submit", "upload", "attach", "upload", "attach"), order)
        assertEquals(1, h.store.feedbackShotCount(reportID), "목록 뒤 칩이 안 섰다")
        assertEquals(h.server.count("feedback_list"), h.server.count("feedback_shots"), "칩 조회는 목록 한 번에 한 번이어야 한다")
        h.assertClean()
    }

    @Test
    fun missingFunctionHidesTheDoorUntilTheScreenOpensAgain() = runTest {
        val h = MeHarness(this) { r ->
            when {
                r.rpcName == "submit_feedback" -> MeReply.Json("\"$reportID\"")
                r.rpcName == "feedback_attach_shot" -> MeReply.missingFunction
                r.rpcName == "feedback_list" -> MeReply.Json("[]")
                r.rpcName == "feedback_reply_latest" -> MeReply.Json("null")
                r.method == "POST" && r.path.startsWith(shotPrefix) -> MeReply.Json("""{"Key":"ok"}""")
                else -> null
            }
        }
        h.store.photoEncoder = fakeEncoder
        h.signIn()
        advanceUntilIdle()
        h.store.attachFeedbackShots(listOf(image()))
        advanceUntilIdle()
        h.store.feedbackDraft = "글"
        h.store.sendFeedback()
        advanceUntilIdle()
        assertEquals(FeedbackShotText.sentShotsDoorClosed, h.store.feedbackNotice)
        assertFalse(h.store.feedbackShotsShown)
        assertFalse(h.store.feedbackShotAttachShown)
        assertTrue(h.store.feedbackShotsForSend.isEmpty())
        val before = h.server.requests.size
        h.store.feedbackDidDisappear()
        h.store.feedbackDidAppear()
        assertTrue(h.store.feedbackShotAttachShown, "다시 열었는데 입구가 숨은 채다")
        advanceUntilIdle()
        assertEquals(0, h.server.requests.drop(before).count { it.rpcName == "feedback_attach_shot" || it.path.startsWith(shotPrefix) })
        h.assertClean()
    }

    @Test
    fun overflowUnreadableAndDoorClosedEachSaySomething() = runTest {
        var attachReply = """{"status":"unsupported_client","door_open":false}"""
        val h = MeHarness(this) { r ->
            when {
                r.rpcName == "submit_feedback" -> MeReply.Json("\"$reportID\"")
                r.rpcName == "feedback_attach_shot" -> MeReply.Json(attachReply)
                r.rpcName == "feedback_list" -> MeReply.Json("[]")
                r.rpcName == "feedback_reply_latest" -> MeReply.Json("null")
                r.method == "POST" && r.path.startsWith(shotPrefix) -> MeReply.Json("""{"Key":"ok"}""")
                else -> null
            }
        }
        // 줄이기가 없는 빌드(데스크톱 · Windows v1)에서는 입구가 없다.
        assertFalse(h.store.feedbackShotsShown)
        h.store.photoEncoder = fakeEncoder
        h.signIn()
        advanceUntilIdle()
        // 넷을 고르면 셋만 붙고 "3장까지".
        h.store.attachFeedbackShots(listOf(image("1"), image("2"), image("3"), image("4")))
        advanceUntilIdle()
        assertEquals(3, h.store.feedbackShots.size)
        assertEquals(FeedbackShotText.full, h.store.feedbackNotice)
        h.store.removeFeedbackShot(h.store.feedbackShots.last().id)
        h.store.removeFeedbackShot(h.store.feedbackShots.last().id)
        // 못 읽는 그림 하나 → "다른 파일을".
        h.store.attachFeedbackShots(listOf("xbroken".encodeToByteArray()))
        advanceUntilIdle()
        assertEquals(1, h.store.feedbackShots.size)
        assertEquals(FeedbackShotText.unreadable, h.store.feedbackNotice)
        // 문 닫힘: 붙이기 줄만 숨고 칩은 남는다 · 다음 장은 시도하지 않는다.
        h.store.attachFeedbackShots(listOf(image("5")))
        advanceUntilIdle()
        h.store.feedbackDraft = "글"
        h.store.sendFeedback()
        advanceUntilIdle()
        assertEquals(FeedbackShotText.sentShotsDoorClosed, h.store.feedbackNotice)
        assertTrue(h.store.feedbackShotsShown)
        assertFalse(h.store.feedbackShotAttachShown)
        assertEquals(1, h.server.count("feedback_attach_shot"), "문이 닫혔는데 다음 캡처를 또 붙였다")
        // 문은 열렸는데 이 판을 안 받는다 → "앱을 최신으로".
        h.store.feedbackDidAppear()
        attachReply = """{"status":"unsupported_client","door_open":true}"""
        h.store.attachFeedbackShots(listOf(image("6")))
        advanceUntilIdle()
        h.store.feedbackDraft = "글 둘"
        h.store.sendFeedback()
        advanceUntilIdle()
        assertEquals(FeedbackShotText.sentShotsAppOutdated, h.store.feedbackNotice)
        h.assertClean()
    }

    @Test
    fun textOnlySendDropsShotsHiddenByTheDoor() = runTest {
        val h = MeHarness(this) { r ->
            when {
                r.rpcName == "submit_feedback" -> MeReply.Json("\"$reportID\"")
                r.rpcName == "feedback_list" -> MeReply.Json("[]")
                r.rpcName == "feedback_reply_latest" -> MeReply.Json("null")
                else -> null
            }
        }
        h.store.photoEncoder = fakeEncoder
        h.signIn()
        advanceUntilIdle()
        h.store.attachFeedbackShots(listOf(image()))
        advanceUntilIdle()
        h.store.feedbackShotDoorClosed = true
        h.store.feedbackDraft = "글만"
        h.store.sendFeedback()
        advanceUntilIdle()
        assertEquals(FeedbackText.sendSuccess, h.store.feedbackNotice)
        assertTrue(h.store.feedbackShots.isEmpty(), "실리지 않은 캡처가 다음 제보에 따라간다")
        assertEquals(0, h.meRequests.count { it.path.startsWith(shotPrefix) || it.rpcName == "feedback_attach_shot" })
        h.assertClean()
    }
}
