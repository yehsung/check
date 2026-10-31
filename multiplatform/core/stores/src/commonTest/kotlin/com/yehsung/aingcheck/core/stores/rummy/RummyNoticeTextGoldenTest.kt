// 원본: Tests/checkTests/GoldenExport/rummy/GoldenExportRummyNotice.swift(골든 생성기) · Tests/checkTests/V0369RummyStatusTextTests.swift @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyPeer
import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 안내 문구가 Swift 글자 그대로다 — 모든 status × 모든 동작. 진단 어휘(서버·상태·동기화·seq)도 안 새야 한다. */
class RummyNoticeTextGoldenTest {
    private val golden = Golden.load("rummy/notice")

    private fun of(kind: String): List<JsonObject> = golden.cases.filter { it.string("kind_") == kind }

    private fun JsonObject.optText(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content

    private fun JsonObject.optIntValue(key: String): Int? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.intOrNull

    @Test
    fun statusTableIsExact() {
        val cases = of("status")
        assertEquals(RummyRPCStatus.entries.map { it.rawValue }.toSet(), cases.map { it.string("status") }.toSet(), "status 어휘가 갈렸다")
        for (case in cases) {
            val status = RummyRPCStatus.entries.first { it.rawValue == case.string("status") }
            val texts = case["texts"]!!.jsonObject
            assertEquals(RummyNoticeText.Action.entries.map { it.rawValue }.toSet(), texts.keys, "동작 어휘가 갈렸다")
            for (action in RummyNoticeText.Action.entries) {
                assertEquals(texts[action.rawValue]!!.jsonPrimitive.content, RummyNoticeText.status(status, action), "${status.rawValue} × ${action.rawValue}")
            }
        }
    }

    @Test
    fun reasonTableIsExact() {
        val cases = of("reason")
        assertEquals(40, cases.size)
        for (case in cases) {
            val reason = RummyTurnReason.entries.first { it.rawValue == case.string("reason") }
            assertEquals(case.optText("text"), RummyNoticeText.reason(reason, case.optIntValue("points")), case.string("id"))
        }
    }

    @Test
    fun invitationAndProgressAreExact() {
        val id = SwiftUUID.parse("00000000-0000-4000-8000-000000000001")!!
        val invitations = of("invitation")
        assertEquals(6, invitations.size)
        for (case in invitations) {
            val hasHost = (case["hasHost"] as JsonPrimitive).booleanOrNull == true
            val room = RummyRoom(
                id = id,
                host = if (hasHost) RummyPeer(id = id, displayName = case.optText("hostName")) else null,
                stake = case.optIntValue("stake")?.toLong(),
            )
            assertEquals(case.string("text"), RummyNoticeText.invitation(room), case.string("id"))
        }
        val progress = of("progress")
        assertEquals(4, progress.size)
        for (case in progress) assertEquals(case.string("text"), RummyNoticeText.initialProgress(case.optIntValue("points")!!), case.string("id"))
    }

    @Test
    fun constantsAreExact() {
        val constants = mapOf(
            "tryAgain" to RummyNoticeText.tryAgain,
            "checkConnection" to RummyNoticeText.checkConnection,
            "updateRequired" to RummyNoticeText.updateRequired,
            "signInAgain" to RummyNoticeText.signInAgain,
            "unavailable" to RummyNoticeText.unavailable,
            "invited" to RummyNoticeText.invited,
            "roomClosed" to RummyNoticeText.roomClosed,
            "droppedFromRoom" to RummyNoticeText.droppedFromRoom,
            "turnPassed" to RummyNoticeText.turnPassed,
            "tableChanged" to RummyNoticeText.tableChanged,
            "finishedMatch" to RummyNoticeText.finishedMatch,
            "myTurnAttention" to RummyNoticeText.myTurnAttention,
            "matchStartedAttention" to RummyNoticeText.matchStartedAttention,
        )
        val cases = of("constant")
        assertEquals(constants.size, cases.size)
        for (case in cases) assertEquals(case.string("text"), constants[case.string("name")], case.string("name"))
    }

    @Test
    fun noDiagnosticWordsLeak() {
        // 설계서 §4.3: 진단 어휘 금지. "상대"(사람)는 쓴다.
        val every = RummyRPCStatus.entries.flatMap { status -> RummyNoticeText.Action.entries.map { RummyNoticeText.status(status, it) } }
        for (text in every) {
            for (word in listOf("서버", "상태", "동기화", "seq", "status", "클릭")) assertFalse(word in text, "'$text' 에 진단·마우스 어휘 '$word'")
        }
        assertTrue(every.isNotEmpty())
    }
}
