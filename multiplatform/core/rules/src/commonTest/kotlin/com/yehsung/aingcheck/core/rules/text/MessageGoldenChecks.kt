// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesMessages.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.datetime.TimeZone
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/** 이력 한 줄(시험용 — 전선 행을 감싸는 자리를 흉내 낸다). */
data class GoldenMessageEntry(
    override val id: String,
    override val peerUserID: String,
    override val peerName: String,
    override val peerAvatarURL: String?,
    override val isMine: Boolean,
    override val isUnread: Boolean?,
    override val createdAt: Double,
) : MessageEntryFacts

/** 메시지 글자 규칙 골든 대조(JVM 시험과 Android 계측이 같은 판정을 부른다). */
object MessageGoldenChecks {
    private fun str(e: JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content
    private fun bool(e: JsonElement?): Boolean? = if (e == null || e is JsonNull) null else e.jsonPrimitive.boolean
    private fun long(e: JsonElement?): Long? = if (e == null || e is JsonNull) null else e.jsonPrimitive.long
    private fun intOrNull(e: JsonElement?): Int? = if (e == null || e is JsonNull) null else e.jsonPrimitive.int
    private fun pairs(e: JsonElement?): Map<String, Int> =
        (e as JsonArray).associate { pair -> pair.jsonArray[0].jsonPrimitive.content to pair.jsonArray[1].jsonPrimitive.int }

    fun entry(o: JsonObject) = GoldenMessageEntry(o.string("id"), o.string("peer"), o.string("name"), str(o["avatar"]),
        o["mine"]!!.jsonPrimitive.boolean, bool(o["unread"]), Golden.bits(o.string("createdAtBits")))

    /** text/message-rules. 돌려주는 값 = 대조한 판 수. */
    fun messageRules(golden: GoldenFile): Int {
        val notices = golden.case("notices")
        assertEquals(notices.int("historyHours"), MessageNoticeText.historyHours)
        assertEquals(notices.int("historyLimit"), MessageNoticeText.historyLimit)
        for ((key, value) in listOf("sent" to MessageNoticeText.sent, "notWorking" to MessageNoticeText.notWorking,
            "targetNotWorking" to MessageNoticeText.targetNotWorking, "targetFocused" to MessageNoticeText.targetFocused,
            "notText" to MessageNoticeText.notText, "blackout" to MessageNoticeText.blackout, "invalid" to MessageNoticeText.invalid,
            "tooLongDefault" to MessageNoticeText.tooLong(), "tooLong40" to MessageNoticeText.tooLong(40), "expiry" to MessageNoticeText.expiry)) {
            assertEquals(notices.string(key), value, golden.failure("notices", key))
        }
        var scenarios = 0
        for (case in golden.cases.filter { it.string("id").startsWith("scenario-") }) {
            val id = case.string("id")
            val entries = case.array("entries").map { entry(it.jsonObject) }
            val serverOrder = case["serverOrder"].let { if (it == null || it is JsonNull) null else pairs(it) }
            val arrival = pairs(case["arrivalOrder"])
            assertEquals(case.array("sorted").map { it.jsonPrimitive.content }, entries.sortedForMessageHistory(serverOrder, arrival).map { it.id },
                golden.failure(id, "sortedForMessageHistory"))
            val threads = MessageThreadBuilder.threads(entries, serverOrder, arrival)
            assertEquals(case.array("threads").map { t ->
                val o = t.jsonObject
                listOf(o.string("peer"), o.string("name"), str(o["avatar"]).toString(), o.array("ids").joinToString(",") { it.jsonPrimitive.content })
            }, threads.map { listOf(it.peerUserID, it.peerName, it.peerAvatarURL.toString(), it.messages.joinToString(",") { m -> m.id }) },
                golden.failure(id, "threads"))
            assertEquals(pairs(case["effectiveOrder"]), MessageUnreadRules.effectiveOrder(entries, serverOrder ?: emptyMap()), golden.failure(id, "effectiveOrder"))
            val historySnapshot = case["historySnapshot"].let {
                if (it == null || it is JsonNull) null else MessageHistoryReadSnapshot(it.jsonObject.int("serial"), serverOrder ?: emptyMap())
            }
            val summary = case["summary"].let {
                if (it == null || it is JsonNull) null
                else MessageUnreadSummarySnapshot(it.jsonObject.int("serial"), it.jsonObject.array("unreadPeerIDs").map { p -> p.jsonPrimitive.content }.toSet())
            }
            val optimistic = case.obj("optimistic").mapValues { (_, v) ->
                val o = v.jsonObject
                MessageOptimisticRead(o.string("throughID"), o.int("recordedSerial"), intOrNull(o["settledSerial"]), o["failed"]!!.jsonPrimitive.boolean)
            }
            val stamps = case.obj("legacyStamps").mapValues { (_, v) -> Golden.bits(v.jsonPrimitive.content) }
            assertEquals(case.array("unreadPeerIDs").map { it.jsonPrimitive.content }.toSet(),
                MessageUnreadRules.unreadPeerIDs(entries, historySnapshot, summary, optimistic, stamps), golden.failure(id, "unreadPeerIDs"))
            val markSnapshot = historySnapshot ?: MessageHistoryReadSnapshot(0, serverOrder ?: emptyMap())
            for (mark in case.array("markTargets")) {
                val m = mark.jsonObject
                val peer = m.string("peer")
                assertEquals(str(m["withRecord"]), MessageUnreadRules.markTarget(peer, entries, markSnapshot, optimistic[peer]), golden.failure(id, "markTarget $peer"))
                assertEquals(str(m["withoutRecord"]), MessageUnreadRules.markTarget(peer, entries, markSnapshot, null), golden.failure(id, "markTarget(기록 없음) $peer"))
            }
            for (read in case.array("alreadyRead")) {
                val r = read.jsonObject
                val messageID = r.string("id")
                assertEquals(r["plain"]!!.jsonPrimitive.boolean, MessageUnreadRules.isAlreadyRead(messageID, entries, historySnapshot, optimistic),
                    golden.failure(id, "isAlreadyRead $messageID"))
                assertEquals(r["withSummary"]!!.jsonPrimitive.boolean, MessageUnreadRules.isAlreadyRead(messageID, entries, historySnapshot, optimistic, summary),
                    golden.failure(id, "isAlreadyRead(요약) $messageID"))
            }
            scenarios++
        }
        assertTrue(scenarios >= 100, "message-rules 시나리오가 너무 적다($scenarios)")
        var zones = 0
        for (case in golden.cases.filter { it.string("id").startsWith("zone-") }) {
            val zone = TimeZone.of(case.string("zone"))
            val id = case.string("id")
            for (row in case.array("rows")) {
                val r = row.jsonObject
                val t = Golden.bits(r.string("tBits"))
                assertEquals(r.string("dayKey"), MessageThreadBuilder.dayKey(t, zone), golden.failure(id, "dayKey ${r.string("tBits")}"))
                assertEquals(r.string("clock"), MessageThreadBuilder.clockText(t, zone), golden.failure(id, "clockText ${r.string("tBits")}"))
                for (label in r.array("labels")) {
                    val l = label.jsonObject
                    assertEquals(l.string("label"), MessageThreadBuilder.dayLabel(t, Golden.bits(l.string("nowBits")), zone),
                        golden.failure(id, "dayLabel ${r.string("tBits")} now ${l.string("nowBits")}"))
                }
            }
            val line = case.array("timelineEntries").map { entry(it.jsonObject) }
            val got = MessageThreadBuilder.timeline(line, Golden.bits(case.string("timelineNowBits")), zone).map { item ->
                when (item) {
                    is MessageTimelineItem.day -> "day:${item.key}:${item.label}:${item.id}"
                    is MessageTimelineItem.bubble -> "bubble:${item.entry.id}:${item.id}"
                }
            }
            val want = case.array("timeline").map { e ->
                val o = e.jsonObject
                if (o["day"] != null) "day:${o.string("day")}:${o.string("label")}:${o.string("id")}" else "bubble:${o.string("bubble")}:${o.string("id")}"
            }
            assertEquals(want, got, golden.failure(id, "timeline"))
            zones++
        }
        assertEquals(5, zones, "시간대 다섯")
        return scenarios
    }

    fun facts(text: String): ServiceErrorFacts = when {
        text == "cancelled" -> ServiceErrorFacts.cancelled
        text == "notServiceError" -> ServiceErrorFacts.notServiceError
        text == "databaseSchemaMissing" -> ServiceErrorFacts.databaseSchemaMissing
        text.startsWith("invalidResponse:") -> ServiceErrorFacts.invalidResponse(text.removePrefix("invalidResponse:").toInt())
        text == "rateLimited" -> ServiceErrorFacts.rateLimited
        text == "otherServiceError" -> ServiceErrorFacts.otherServiceError
        else -> fail("모르는 오류 사실 $text")
    }

    /** text/block-report. */
    fun blockReport(golden: GoldenFile) {
        for (platform in BlockReportPlatform.entries) {
            val case = golden.case("text-${platform.name}")
            assertEquals(case.array("blockConfirmItems").map { it.jsonPrimitive.content }, BlockReportText.blockConfirmItems(platform))
            assertEquals(case.string("blockedListPath"), BlockReportText.blockedListPath(platform))
            assertEquals(case.string("blockConfirmUndoNote"), BlockReportText.blockConfirmUndoNote(platform))
            assertEquals(case.string("blockedListLede"), BlockReportText.blockedListLede(platform))
            assertEquals(case.string("blockedEmptyMessage"), BlockReportText.blockedEmptyMessage(platform))
        }
        val constants = golden.case("constants")
        val values = constants.obj("values")
        val mine = linkedMapOf<String, Any>(
            "menuAccessibilityLabel" to BlockReportText.menuAccessibilityLabel, "blockAction" to BlockReportText.blockAction,
            "reportAction" to BlockReportText.reportAction, "reportMessageAction" to BlockReportText.reportMessageAction,
            "blockedMessagesFact" to BlockReportText.blockedMessagesFact, "blockConfirmScopeNote" to BlockReportText.blockConfirmScopeNote,
            "blockConfirm" to BlockReportText.blockConfirm, "blockCancel" to BlockReportText.blockCancel, "reportTitle" to BlockReportText.reportTitle,
            "reportMessageLede" to BlockReportText.reportMessageLede, "reportReasonHeader" to BlockReportText.reportReasonHeader,
            "reportDetailHeader" to BlockReportText.reportDetailHeader, "reportDetailPlaceholder" to BlockReportText.reportDetailPlaceholder,
            "reportAlsoBlock" to BlockReportText.reportAlsoBlock, "reportAlsoBlockDetail" to BlockReportText.reportAlsoBlockDetail,
            "reviewPromise" to BlockReportText.reviewPromise, "reportSubmit" to BlockReportText.reportSubmit, "reportSending" to BlockReportText.reportSending,
            "reportReasonRequired" to BlockReportText.reportReasonRequired, "reportDetailOverflow200" to BlockReportText.reportDetailOverflow(200),
            "blockedListTitle" to BlockReportText.blockedListTitle, "blockedListMenuDetail" to BlockReportText.blockedListMenuDetail,
            "blockedEmptyTitle" to BlockReportText.blockedEmptyTitle, "blockedListFailed" to BlockReportText.blockedListFailed,
            "unblockAction" to BlockReportText.unblockAction, "unblockConfirmMessage" to BlockReportText.unblockConfirmMessage,
            "unblockConfirm" to BlockReportText.unblockConfirm, "reportSentNotice" to BlockReportText.reportSentNotice,
            "serverNotReady" to BlockReportText.serverNotReady, "checkConnection" to BlockReportText.checkConnection,
            "counterThreshold" to BlockReportRules.counterThreshold, "detailMaxLength" to ContentReportDetail.maxLength,
        )
        constants.array("names").forEachIndexed { index, nameElement ->
            val name = nameElement.jsonPrimitive.content
            mine["blockConfirmTitle:$index"] = BlockReportText.blockConfirmTitle(name)
            mine["reportLede:$index"] = BlockReportText.reportLede(name)
            mine["unblockConfirmTitle:$index"] = BlockReportText.unblockConfirmTitle(name)
            mine["blockedNotice:$index"] = BlockReportText.blockedNotice(name)
            mine["blockedAtLine:$index"] = BlockReportText.blockedAtLine(name)
        }
        assertEquals(values.keys, mine.keys, "block-report 상수 이름 집합")
        for ((key, value) in mine) assertEquals(values[key]!!.jsonPrimitive.content, value.toString(), golden.failure("constants", key))
        var errors = 0
        for (case in golden.cases.filter { it.string("id").startsWith("error-") }) {
            val id = case.string("id")
            val fact = facts(case.string("facts"))
            assertEquals(case["isMissingFunction"]!!.jsonPrimitive.boolean, BlockReportRules.isMissingFunction(fact), golden.failure(id, "isMissingFunction"))
            val failure = BlockReportRules.classify(fact)
            assertEquals(case.string("failure"), failure.name, golden.failure(id, "classify"))
            assertEquals(str(case["noticeBlock"]), BlockReportRules.notice(failure, BlockReportAction.block), golden.failure(id, "notice block"))
            assertEquals(str(case["noticeUnblock"]), BlockReportRules.notice(failure, BlockReportAction.unblock), golden.failure(id, "notice unblock"))
            assertEquals(str(case["noticeReport"]), BlockReportRules.notice(failure, BlockReportAction.report), golden.failure(id, "notice report"))
            errors++
        }
        assertTrue(errors >= 15, "오류 표가 너무 짧다($errors)")
        for (case in golden.cases.filter { it.string("id").startsWith("detail-") }) {
            val id = case.string("id")
            val raw = TextGoldenChecks.text(case.string("cps"))
            assertEquals(case.string("sanitized"), TextGoldenChecks.cps(ContentReportDetail.sanitized(raw)), golden.failure(id, "sanitized"))
            assertEquals(case.int("length"), ContentReportDetail.length(raw), golden.failure(id, "length"))
            assertEquals(case["withinLimit"]!!.jsonPrimitive.boolean, ContentReportDetail.isWithinLimit(raw), golden.failure(id, "withinLimit"))
            assertEquals(str(case["payload"]), ContentReportDetail.payload(raw)?.let(TextGoldenChecks::cps), golden.failure(id, "payload"))
            assertEquals(str(case["counter"]), BlockReportRules.detailCounterText(raw), golden.failure(id, "counter"))
            assertEquals(case["overflowing"]!!.jsonPrimitive.boolean, BlockReportRules.isDetailOverflowing(raw), golden.failure(id, "overflowing"))
            assertEquals(case["canSubmit"]!!.jsonPrimitive.boolean, BlockReportRules.canSubmitReport(true, raw, false), golden.failure(id, "canSubmit"))
            assertEquals(case["canSubmitNoReason"]!!.jsonPrimitive.boolean, BlockReportRules.canSubmitReport(false, raw, false), golden.failure(id, "canSubmit(사유 없음)"))
            assertEquals(case["canSubmitSending"]!!.jsonPrimitive.boolean, BlockReportRules.canSubmitReport(true, raw, true), golden.failure(id, "canSubmit(보내는 중)"))
        }
    }

    private fun infoOf(e: JsonElement?): MegaphoneInfo? {
        if (e == null || e is JsonNull) return null
        val o = e.jsonObject
        return MegaphoneInfo(o["enabled"]!!.jsonPrimitive.boolean, o["price"]!!.jsonPrimitive.long, o["recipients"]!!.jsonPrimitive.long,
            o["maxLength"]!!.jsonPrimitive.long, o["cooldownSeconds"]!!.jsonPrimitive.long, str(o["cooldownEndsAtBits"])?.let(Golden::bits))
    }

    private fun infoJson(info: MegaphoneInfo?): String = info?.let {
        "enabled=${it.enabled} price=${it.price} recipients=${it.recipients} maxLength=${it.maxLength} cooldown=${it.cooldownSeconds} " +
            "ends=${it.cooldownEndsAt?.let(Golden::bitsText)}"
    } ?: "nil"

    /** Swift 열거값의 `"\(value)"` 꼴(연관값 Optional 은 Optional(n) · nil). */
    fun swiftDescription(outcome: MegaphoneSendOutcome): String {
        fun opt(v: Long?) = v?.let { "Optional($it)" } ?: "nil"
        return when (outcome) {
            is MegaphoneSendOutcome.sent -> "sent(recipients: ${outcome.recipients}, duplicate: ${outcome.duplicate})"
            is MegaphoneSendOutcome.insufficient -> "insufficient(need: ${opt(outcome.need)}, have: ${opt(outcome.have)})"
            is MegaphoneSendOutcome.cooldown -> "cooldown(retryAfterSeconds: ${opt(outcome.retryAfterSeconds)})"
            is MegaphoneSendOutcome.tooLong -> "tooLong(maxLength: ${opt(outcome.maxLength)})"
            MegaphoneSendOutcome.noRecipients -> "noRecipients"
            MegaphoneSendOutcome.empty -> "empty"
            MegaphoneSendOutcome.notText -> "notText"
            MegaphoneSendOutcome.disabled -> "disabled"
            MegaphoneSendOutcome.blackout -> "blackout"
            MegaphoneSendOutcome.unavailable -> "unavailable"
            MegaphoneSendOutcome.failed -> "failed"
        }
    }

    /**
     * Swift 기준선(이 레인 골든 = main 75c31cd2) **뒤에** 바뀐 확성기 작성 문구 — main a6791165(b056075b) · 계약 C4(사용자 결정: 받는 쪽 화면에
     * 배너로 뜬다). 골든이 옛 문구일 때만 새 문구로 갈아 잰다. 골든을 a6791165 이후로 다시 뜨면 옛 문구가 사라져 여기서 빨갛다 — 그때 이 표를 지운다.
     * 이 두 키(와 reach 인 infoLine 줄) 말고는 갈지 않는다.
     */
    private fun megaphoneAfterBaseline(key: String, golden: String): String = when (key) {
        "explainer" -> {
            assertEquals("앱을 쓰는 모두에게 메시지로 가요 · 집중 중인 사람은 빼요", golden, "골든이 새 기준선이다 — megaphoneAfterBaseline 표를 지운다")
            "앱 사용자 모두의 화면에 크게 떠요 · 집중 중인 사람은 빼요"
        }
        "reach" -> megaphoneReachBefore.matchEntire(golden)?.let { "지금 보내면 ${it.groupValues[1]}명의 화면에 떠요" }
            ?: fail("골든이 새 기준선이다 — megaphoneAfterBaseline 표를 지운다: $golden")
        // 작성 화면 한 줄(infoLine)은 reach 일 때만 간다(대기 · 받을 사람 없음 · 못 읽음 문구는 그대로).
        "infoLine" -> if (megaphoneReachBefore.matches(golden)) megaphoneAfterBaseline("reach", golden) else golden
        else -> golden
    }

    private val megaphoneReachBefore = Regex("^지금 보내면 (\\d+)명에게 가요$")

    /** text/megaphone. */
    fun megaphone(golden: GoldenFile) {
        val c = golden.case("constants")
        assertEquals(c.string("prefix"), TextGoldenChecks.cps(MegaphoneBody.prefix))
        assertEquals(c.int("maxLength"), MegaphoneBody.maxLength)
        assertEquals(c.int("defaultCooldownSeconds").toLong(), MegaphoneRules.defaultCooldownSeconds)
        for ((key, value) in listOf("title" to MegaphoneText.title, "badgeTitle" to MegaphoneText.badgeTitle, "explainer" to MegaphoneText.explainer,
            "placeholder" to MegaphoneText.placeholder, "sendButton" to MegaphoneText.sendButton, "cancelButton" to MegaphoneText.cancelButton,
            "noRecipients" to MegaphoneText.noRecipients, "unavailable" to MegaphoneText.unavailable, "empty" to MegaphoneText.empty,
            "notText" to MegaphoneText.notText, "blackout" to MegaphoneText.blackout, "connection" to MegaphoneText.connection,
            "failed" to MegaphoneText.failed, "loadingInfo" to MegaphoneText.loadingInfo, "infoFailed" to MegaphoneText.infoFailed,
            "tooLongNil" to MegaphoneText.tooLong(null), "tooLong50" to MegaphoneText.tooLong(50), "counter" to MegaphoneText.counter(12, 197))) {
            assertEquals(megaphoneAfterBaseline(key, c.string(key)), value, golden.failure("constants", key))
        }
        assertEquals(c.string("icon"), TextGoldenChecks.cps(MegaphoneText.icon))
        for (row in c.array("minutes")) {
            val r = row.jsonObject
            val seconds = r.int("seconds").toLong()
            assertEquals(r.int("minutes").toLong(), MegaphoneText.cooldownMinutes(seconds), "cooldownMinutes $seconds")
            assertEquals(r.string("text"), MegaphoneText.cooldown(seconds), "cooldown $seconds")
        }
        for (row in c.array("numbers")) {
            val r = row.jsonObject
            val n = r.int("n").toLong()
            assertEquals(r.string("sent"), MegaphoneText.sent(n))
            assertEquals(r.string("alreadySent"), MegaphoneText.alreadySent(n))
            assertEquals(megaphoneAfterBaseline("reach", r.string("reach")), MegaphoneText.reach(n))
            assertEquals(r.string("confirm"), MegaphoneText.confirm(n + 5, n))
        }
        for (row in c.array("shortfall")) {
            val r = row.jsonObject
            assertEquals(r.string("text"), MegaphoneText.shortfall(long(r["need"]), long(r["have"])))
        }
        fun describe(v: MessageBodyValidation): String = when (v) {
            is MessageBodyValidation.ok -> "ok:" + TextGoldenChecks.cps(v.value)
            MessageBodyValidation.empty -> "empty"
            is MessageBodyValidation.tooLong -> "tooLong:" + v.maxLength
        }
        fun describe(o: JsonObject): String = when {
            o["ok"] != null -> "ok:" + o.string("ok")
            o["empty"] != null -> "empty"
            else -> "tooLong:" + o.int("tooLong")
        }
        for (case in golden.cases.filter { it.string("id").startsWith("body-") }) {
            val id = case.string("id")
            val raw = TextGoldenChecks.text(case.string("cps"))
            assertEquals(case.int("length"), MegaphoneBody.length(raw), golden.failure(id, "length"))
            assertEquals(describe(case.obj("validate")), describe(MegaphoneBody.validate(raw)), golden.failure(id, "validate"))
            assertEquals(describe(case.obj("validate10")), describe(MegaphoneBody.validate(raw, 10)), golden.failure(id, "validate(10)"))
            val refusal = MegaphoneBody.localRefusal(raw)
            when (val v = MegaphoneBody.validate(raw)) {
                is MessageBodyValidation.ok -> assertEquals(null, refusal, golden.failure(id, "localRefusal"))
                MessageBodyValidation.empty -> assertEquals("empty", refusal?.status, golden.failure(id, "localRefusal"))
                is MessageBodyValidation.tooLong -> assertEquals(v.maxLength.toLong(), refusal?.maxLength, golden.failure(id, "localRefusal"))
            }
        }
        val requests = listOf(SendMegaphoneRequest("모두 안녕/하세요", "0000abcd-0000-4000-8000-000000000001"), SendMegaphoneRequest("", ""))
        requests.forEachIndexed { index, request ->
            assertEquals(Json.parseToJsonElement(golden.case("request-$index").string("json")), request.body(), "request-$index")
        }
        var infos = 0
        for (case in golden.cases.filter { it.string("id").startsWith("info-") }) {
            val id = case.string("id")
            val response = try { MegaphoneInfoResponse.decode(parseSwiftJson(case.string("json"))) } catch (e: SwiftDecodingError) { null }
            if (case["throws"] != null) {
                assertEquals(null, response, golden.failure(id, "Swift 는 디코드를 거절했다"))
                continue
            }
            response!!
            val r = case.obj("response")
            assertEquals(listOf(str(r["status"]), bool(r["enabled"]).toString(), long(r["price"]).toString(), long(r["cooldownSeconds"]).toString(),
                long(r["cooldownRemainingSeconds"]).toString(), long(r["recipients"]).toString(), long(r["maxLength"]).toString(), long(r["rubyBalance"]).toString()),
                listOf(response.status, response.enabled.toString(), response.price.toString(), response.cooldownSeconds.toString(),
                    response.cooldownRemainingSeconds.toString(), response.recipients.toString(), response.maxLength.toString(), response.rubyBalance.toString()),
                golden.failure(id, "decode"))
            for (row in case.array("rows")) {
                val o = row.jsonObject
                val now = 1_792_998_000.5
                val info = MegaphoneInfo.from(response, now)
                assertEquals(infoJson(infoOf(o["info"])), infoJson(info), golden.failure(id, "MegaphoneInfo.from"))
                assertEquals(o["infoFailed"]!!.jsonPrimitive.boolean, info == null, golden.failure(id, "infoFailed"))
                assertEquals(long(o["rubyAfter"]), MegaphoneRules.rubyAfterInfo(response, info, long(o["ruby"])), golden.failure(id, "ruby 미러"))
                for (line in o.array("lines")) {
                    val l = line.jsonObject
                    val t = Golden.bits(l.string("nowBits"))
                    assertEquals(megaphoneAfterBaseline("infoLine", l.string("line")), MegaphoneRules.infoLine(false, info, info == null, t),
                        golden.failure(id, "infoLine"))
                    assertEquals(l.int("remaining").toLong(), info?.cooldownRemaining(t) ?: -1L, golden.failure(id, "cooldownRemaining"))
                }
            }
            infos++
        }
        assertTrue(infos >= 8, "info 판이 너무 적다($infos)")
        var sends = 0
        for (case in golden.cases.filter { it.string("id").startsWith("send-") }) {
            val id = case.string("id")
            val response = try { MegaphoneSendResponse.decode(parseSwiftJson(case.string("json"))) } catch (e: SwiftDecodingError) { null }
            if (case["throws"] != null) {
                assertEquals(null, response, golden.failure(id, "Swift 는 디코드를 거절했다"))
                continue
            }
            response!!
            val outcome = MegaphoneSendOutcome.from(response)
            assertEquals(case.string("outcome"), swiftDescription(outcome), golden.failure(id, "결과"))
            for (row in case.array("rows")) {
                val o = row.jsonObject
                val now = 1_792_998_000.25
                val before = if (o["withInfo"]!!.jsonPrimitive.boolean) {
                    MegaphoneInfo.from(MegaphoneInfoResponse(status = "ok", enabled = true, price = 30, cooldownSeconds = 300, recipients = 9, maxLength = 197), now)
                } else null
                assertEquals(infoJson(infoOf(o["infoBefore"])), infoJson(before), golden.failure(id, "정보(전)"))
                val left = if (outcome is MegaphoneSendOutcome.cooldown) MegaphoneRules.cooldownSecondsAfter(outcome, before) else 0
                val (notice, isError) = MegaphoneText.notice(outcome, left)
                assertEquals(str(o["notice"]), notice, golden.failure(id, "문구"))
                assertEquals(o["noticeIsError"]!!.jsonPrimitive.boolean, isError, golden.failure(id, "오류 표시"))
                assertEquals(infoJson(infoOf(o["info"])), infoJson(MegaphoneRules.infoAfter(outcome, before, now)), golden.failure(id, "정보(뒤)"))
                assertEquals(long(o["rubyAfter"]), MegaphoneRules.rubyAfterSend(response, 50), golden.failure(id, "ruby 미러"))
                assertEquals(o["serverUnavailable"]!!.jsonPrimitive.boolean, outcome == MegaphoneSendOutcome.unavailable, golden.failure(id, "serverUnavailable"))
            }
            sends++
        }
        assertTrue(sends >= 15, "send 판이 너무 적다($sends)")
        val gate = golden.case("gate")
        val now = Golden.bits(gate.string("nowBits"))
        var gates = 0
        for (row in gate.array("rows")) {
            val o = row.jsonObject
            val result = MegaphoneRules.requestSend(false, true, o["serverUnavailable"]!!.jsonPrimitive.boolean, TextGoldenChecks.text(o.string("draft")),
                infoOf(o["infoBefore"]), o["infoFailed"]!!.jsonPrimitive.boolean, long(o["ruby"]), now)
            val label = "gate ${o.string("info")} draft=${o.string("draft")} ruby=${long(o["ruby"])} flags=${o.int("flags")}"
            when (result) {
                MegaphoneSendGate.confirm -> {
                    assertTrue(o["confirming"]!!.jsonPrimitive.boolean, "$label: Swift 는 확인으로 안 갔다")
                    assertEquals(null, str(o["notice"]), label)
                    assertEquals(false, o["reloading"]!!.jsonPrimitive.boolean, label)
                }
                is MegaphoneSendGate.notice -> {
                    assertEquals(false, o["confirming"]!!.jsonPrimitive.boolean, "$label: Swift 는 확인으로 갔다")
                    assertEquals(str(o["notice"]), result.text, label)
                    assertEquals(o["noticeIsError"]!!.jsonPrimitive.boolean, result.isError, label)
                    assertEquals(o["reloading"]!!.jsonPrimitive.boolean, result.reloadInfo, label)
                }
                MegaphoneSendGate.ignore -> fail("$label: 무시할 이유가 없다")
            }
            gates++
        }
        assertTrue(gates >= 200, "gate 줄이 너무 적다($gates)")
        for (row in golden.case("request-ids").array("rows")) {
            val o = row.jsonObject
            val fact = facts(o.string("facts"))
            assertEquals(o["isMissingFunction"]!!.jsonPrimitive.boolean, BlockReportRules.isMissingFunction(fact), o.string("failure"))
            val ids = MegaphoneRequestID()
            var made = 0
            var serverUnavailable = false
            var confirming = true
            for (step in o.array("steps")) {
                val s = step.jsonObject
                val started = !serverUnavailable && confirming
                assertEquals(s["started"]!!.jsonPrimitive.boolean, started, "${o.string("failure")} started")
                if (!started) continue
                val sent = ids.begin { made += 1; "REQ-$made" }
                assertEquals(str(s["sentID"]), sent, "${o.string("failure")} sentID")
                val effect = MegaphoneRules.afterSendFailure(fact)
                ids.failed(effect.dropRequestID)
                if (effect.serverUnavailable) serverUnavailable = true
                if (effect.endsConfirm) confirming = false
                assertEquals(str(s["pendingAfter"]), ids.pending, "${o.string("failure")} pendingAfter")
                assertEquals(str(s["notice"]), effect.notice, "${o.string("failure")} notice")
                assertEquals(s["confirming"]!!.jsonPrimitive.boolean, confirming, "${o.string("failure")} confirming")
                assertEquals(s["serverUnavailable"]!!.jsonPrimitive.boolean, serverUnavailable, "${o.string("failure")} serverUnavailable")
            }
            ids.pending?.let(ids::settle)
            assertEquals(str(o["pendingAfterSettle"]), ids.pending, "${o.string("failure")} settle")
            assertEquals(o.int("made"), made, "${o.string("failure")} made")
        }
    }
}
