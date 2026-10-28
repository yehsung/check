// 원본: 없음 — 골든 messages/*(Swift 생성기 Tests/CheckMobileKitTests/GoldenExport/messages/GoldenExportMessages.swift)를 Kotlin 규칙에 대조한다.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageHistoryReadSnapshot
import com.yehsung.aingcheck.core.rules.text.MessageOptimisticRead
import com.yehsung.aingcheck.core.rules.text.MessageThreadBuilder
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.rules.text.sortedForMessageHistory
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogKind
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import com.yehsung.aingcheck.core.wire.models.MessageUnreadPeer
import com.yehsung.aingcheck.core.wire.models.MessageUnreadSummary
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.sortedForPokeDisplay
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.isJsonNull
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/** 골든 칸 읽기(널 허용 칸 · 쌍 배열). */
internal object G {
    fun optString(o: JsonObject, key: String): String? = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun optInt(o: JsonObject, key: String): Int? = (o[key] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
    fun optBool(o: JsonObject, key: String): Boolean? = (o[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
    fun bool(o: JsonObject, key: String): Boolean = optBool(o, key) ?: error("골든 칸 '$key' 가 불이 아니다: ${o[key]}")
    fun strings(o: JsonObject, key: String): List<String> = o.array(key).map { it.stringValue() }
    fun set(o: JsonObject, key: String): Set<String> = strings(o, key).toSet()
    fun pairs(element: JsonElement?): Map<String, Int> {
        if (element == null || element.isJsonNull()) return emptyMap()
        return element.jsonArray.associate { pair ->
            val items = pair.jsonArray
            items[0].stringValue() to items[1].jsonPrimitive.intOrNull!!
        }
    }

    fun date(o: JsonObject, key: String): SwiftDate = SwiftDate(o.bits(key))
    fun bits(date: SwiftDate): String = Golden.bitsText(date.timeIntervalSince1970)

    fun entry(o: JsonObject): MessageEntry = MessageEntry(
        MessageHistoryEntry(
            id = o.string("id"), peerUserID = o.string("peer"), peerName = o.string("name"),
            peerAvatarURL = SwiftURL.parse(optString(o, "avatar")), body = o.string("body"), createdAt = date(o, "createdAtBits"),
            isMine = bool(o, "mine"), readByPeer = optBool(o, "readByPeer"), isUnread = optBool(o, "unread"),
        ),
    )

    fun poke(o: JsonObject): MessagePokeLogEntry = MessagePokeLogEntry(
        id = o.string("id"), peerUserID = o.string("peer"), peerName = o.string("name"), peerAvatarURL = SwiftURL.parse(optString(o, "avatar")),
        createdAt = date(o, "createdAtBits"), isMine = bool(o, "mine"),
        kind = MessagePokeLogKind.of(o.string("kind")) ?: error("모르는 찌르기 종류 ${o.string("kind")}"), isUnread = optBool(o, "unread"),
    )

    fun entries(o: JsonObject, key: String): List<MessageEntry> = o.array(key).map { entry(it.jsonObject) }
    fun pokes(o: JsonObject, key: String): List<MessagePokeLogEntry> = o.array(key).map { poke(it.jsonObject) }

    fun optimistic(o: JsonObject, key: String): Map<String, MessageOptimisticRead> = o.array(key).associate { element ->
        val r = element.jsonObject
        r.string("peer") to MessageOptimisticRead(r.string("throughID"), r.int("recordedSerial"), optInt(r, "settledSerial"), bool(r, "failed"))
    }

    fun pending(o: JsonObject, key: String, peerOf: (JsonObject) -> String, createdAt: (JsonObject) -> SwiftDate): List<MessagesPendingOutgoing> =
        o.array(key).map { element ->
            val p = element.jsonObject
            val state = p["state"] as JsonPrimitive
            MessagesPendingOutgoing(
                id = p.string("id"), peerUserID = peerOf(p), body = p.string("body"), createdAt = createdAt(p),
                state = if (state.isString) MessagesPendingOutgoing.State.sending else MessagesPendingOutgoing.State.sent(state.intOrNull!!),
            )
        }

    fun check(file: GoldenFile, caseID: String, label: String, expected: Any?, actual: Any?) {
        assertEquals(expected, actual, file.failure(caseID, "$label 가 Swift 와 다르다"))
    }
}

class MessagesGoldenTest {
    private val kst = MessagesTime.kst

    @Test
    fun pokeDisplaySortAndDirectorySearchMatchSwift() {
        val file = Golden.load("messages/poke-display-sort")
        var sorts = 0
        var searches = 0
        for (c in file.cases) {
            val id = c.string("id")
            val entries = c.array("entries").map {
                val e = it.jsonObject
                PokeDirectoryEntry(userID = e.string("id"), name = e.string("name"), avatarURL = null, isWorking = G.bool(e, "working"))
            }
            val unread = G.set(c, "unread")
            if (id.startsWith("sort-")) {
                val sorted = entries.sortedForPokeDisplay(unreadPeerIDs = unread, workKnown = G.bool(c, "workKnown"), collation = NaturalKoNameCollation)
                G.check(file, id, "sorted", G.strings(c, "sorted"), sorted.map { it.userID })
                sorts += 1
            } else if (!id.startsWith("directory-")) {
                // 모르는 접두는 조용히 건너뛰지 않는다 — 생성기가 id 를 바꾸면 그 케이스를 아무도 대조하지 않게 된다(검증 V14).
                fail("모르는 case id: $id (poke-display-sort 는 sort-* · directory-* 만)")
            } else {
                for (r in c.array("results")) {
                    val result = r.jsonObject
                    val query = result.string("query")
                    val filtered = MessagesDirectoryRules.filter(entries, query, unreadPeerIDs = unread, collation = NaturalKoNameCollation)
                    G.check(file, id, "filter('$query')", G.strings(result, "ids"), filtered.map { it.userID })
                    searches += 1
                }
                for (r in c.array("initials")) {
                    val o = r.jsonObject
                    G.check(file, id, "initials(${o.string("name")})", o.string("initials"), MessagesDirectoryRules.initials(o.string("name")))
                }
            }
        }
        assertTrue(sorts >= 45 && searches >= 40, "골든이 비었다(정렬 $sorts · 검색 $searches)")
    }

    @Test
    fun threadListRowsMatchSwift() {
        val file = Golden.load("messages/thread-list")
        var rowsSeen = 0
        for (c in file.cases) {
            val id = c.string("id")
            if (id == "rank-table") {
                for (r in c.array("ranks")) {
                    val o = r.jsonObject
                    G.check(file, id, "rank $o", o.int("rank"), MessagesSortRules.rank(G.bool(o, "unread"), G.bool(o, "working"), G.bool(o, "known")))
                }
                continue
            }
            if (!id.startsWith("rows-")) fail("모르는 case id: $id (thread-list 는 rank-table · rows-* 만)")
            val entries = G.entries(c, "entries")
            val serverOrder = c["serverOrder"]?.takeIf { !it.isJsonNull() }?.let { G.pairs(it) }
            val threads = MessageThreadBuilder.threads(entries, serverOrder)
            val rows = MessagesThreadListRules.rows(
                threads = threads,
                pokes = G.pokes(c, "pokes"),
                chronology = G.pairs(c["chronology"]),
                messageUnreadPeerIDs = G.set(c, "messageUnread"),
                pokeUnreadPeerIDs = G.set(c, "pokeUnread"),
                unreadCounts = G.pairs(c["counts"]),
                workingPeerIDs = G.set(c, "working"),
                workKnown = G.bool(c, "workKnown"),
                now = G.date(c, "nowBits"),
                zone = kst,
            )
            val expected = c.array("rows").map { it.jsonObject }
            G.check(file, id, "rows.peer", expected.map { it.string("peer") }, rows.map { it.peerUserID })
            for ((row, e) in rows.zip(expected)) {
                val label = "row ${row.peerUserID}"
                G.check(file, id, "$label.name", e.string("name"), row.peerName)
                G.check(file, id, "$label.avatar", G.optString(e, "avatar"), row.peerAvatarURL)
                G.check(file, id, "$label.messageIDs", G.strings(e, "messageIDs"), row.thread.messages.map { it.id })
                G.check(file, id, "$label.pokeIDs", G.strings(e, "pokeIDs"), row.pokes.map { it.id })
                G.check(file, id, "$label.lastActivity", e.string("lastActivityBits"), G.bits(row.lastActivityAt))
                G.check(file, id, "$label.preview", e.string("preview"), row.previewText)
                G.check(file, id, "$label.lastIsMine", G.bool(e, "lastIsMine"), row.lastIsMine)
                G.check(file, id, "$label.previewIsPoke", G.bool(e, "previewIsPoke"), row.previewIsPoke)
                G.check(file, id, "$label.timeText", e.string("timeText"), row.timeText)
                G.check(file, id, "$label.isUnread", G.bool(e, "isUnread"), row.isUnread)
                G.check(file, id, "$label.countBadge", G.optString(e, "countBadge"), row.countBadge)
                G.check(file, id, "$label.group", e.int("group"), row.group)
                G.check(file, id, "$label.a11y", e.string("a11y"), MessagesThreadListRules.accessibilityText(row, null))
                G.check(file, id, "$label.a11yPresence", e.string("a11yPresence"), MessagesThreadListRules.accessibilityText(row, "근무 중"))
                rowsSeen += 1
            }
        }
        assertTrue(rowsSeen >= 30, "골든 줄이 너무 적다($rowsSeen)")
    }

    @Test
    fun pokeLogRulesTimelineAndConversationItemsMatchSwift() {
        val file = Golden.load("messages/poke-log")
        for (c in file.cases) {
            val id = c.string("id")
            val pokes = G.pokes(c, "pokes")
            val entries = G.entries(c, "entries")
            val chronology = G.pairs(c["chronology"])
            val snapshot = MessageHistoryReadSnapshot(c.int("snapshotSerial"), chronology)
            val optimistic = G.optimistic(c, "optimistic")
            val now = G.date(c, "nowBits")
            G.check(file, id, "effectiveOrder", G.pairs(c["effectiveOrder"]), MessagePokeLogRules.effectiveOrder(pokes, chronology))
            G.check(file, id, "unreadPeerIDs", G.set(c, "unreadPeerIDs"), MessagePokeLogRules.unreadPeerIDs(pokes, snapshot, optimistic))
            for (m in c.array("markTargets")) {
                val o = m.jsonObject
                val peer = o.string("peer")
                G.check(file, id, "markTarget($peer, record)", G.optString(o, "withRecord"),
                    MessagePokeLogRules.markTarget(peer, pokes, snapshot, optimistic[peer]))
                G.check(file, id, "markTarget($peer)", G.optString(o, "withoutRecord"), MessagePokeLogRules.markTarget(peer, pokes, snapshot, null))
            }
            G.check(file, id, "sorted", G.strings(c, "sorted"), MessagePokeLogRules.sorted(pokes, chronology, G.pairs(c["arrival"])).map { it.id })
            val sortedMessages = entries.sortedForMessageHistory(chronology)
            G.check(file, id, "sortedMessages", G.strings(c, "sortedMessages"), sortedMessages.map { it.id })
            val lines = MessageConversationTimeline.lines(sortedMessages, MessagePokeLogRules.sorted(pokes, chronology), chronology, now.timeIntervalSince1970, kst)
            val expectedLines = c.array("lines").map { it.jsonObject }
            G.check(file, id, "lines.count", expectedLines.size, lines.size)
            for ((line, e) in lines.zip(expectedLines)) {
                when (line) {
                    is MessageConversationLine.day -> {
                        G.check(file, id, "line.kind", e.string("kind"), "day")
                        G.check(file, id, "day.key", e.string("key"), line.key)
                        G.check(file, id, "day.label", e.string("label"), line.label)
                    }
                    is MessageConversationLine.bubble -> {
                        G.check(file, id, "line.kind", e.string("kind"), "bubble")
                        G.check(file, id, "bubble.id", e.string("id"), line.entry.id)
                    }
                    is MessageConversationLine.poke -> {
                        G.check(file, id, "line.kind", e.string("kind"), "poke")
                        G.check(file, id, "poke.id", e.string("id"), line.entry.id)
                        G.check(file, id, "poke.lineID", e.string("lineID"), line.id)
                    }
                }
            }
            for (t in c.array("texts")) {
                val o = t.jsonObject
                val poke = pokes.first { it.id == o.string("id") }
                G.check(file, id, "line(${poke.id})", o.string("line"), MessagePokeLogText.line(poke, kst))
                G.check(file, id, "symbol(${poke.id})", o.string("symbol"), MessagePokeLogText.symbol(poke.kind))
                G.check(file, id, "pokePreview(${poke.id})", o.string("preview"), MessagesSortRules.pokePreview(poke, kst))
            }
            val peer = c.string("conversationPeer")
            val thread = MessageThreadBuilder.threads(entries, chronology).firstOrNull { it.peerUserID == peer }
            val pending = G.pending(c, "pending", peerOf = { peer }, createdAt = { now })
            val items = MessagesConversationRules.items(
                messages = thread?.messages ?: emptyList(), pokes = pokes.filter { it.peerUserID == peer }, chronology = chronology,
                pending = pending, receiptsAvailable = G.bool(c, "receipts"), now = now, zone = kst,
            )
            val expectedItems = c.array("items").map { it.jsonObject }
            G.check(file, id, "items.id", expectedItems.map { it.string("id") }, items.map { it.id })
            for ((item, e) in items.zip(expectedItems)) {
                when (item) {
                    is MessagesConversationItem.day -> {
                        G.check(file, id, "item.kind", e.string("kind"), "day")
                        G.check(file, id, "item.label", e.string("label"), item.label)
                    }
                    is MessagesConversationItem.bubble -> {
                        G.check(file, id, "item.kind", e.string("kind"), "bubble")
                        G.check(file, id, "bubble.clock", e.string("clock"), item.line.clockText)
                        G.check(file, id, "bubble.showsTime", G.bool(e, "showsTime"), item.line.showsTime)
                        G.check(file, id, "bubble.startsGroup", G.bool(e, "startsGroup"), item.line.startsGroup)
                        G.check(file, id, "bubble.unreadOne", G.bool(e, "unreadOne"), item.line.showsUnreadOne)
                        G.check(file, id, "bubble.mine", G.bool(e, "mine"), item.isMine)
                    }
                    is MessagesConversationItem.poke -> {
                        G.check(file, id, "item.kind", e.string("kind"), "poke")
                        G.check(file, id, "poke.text", e.string("text"), item.line.text)
                        G.check(file, id, "poke.symbol", e.string("symbol"), item.line.symbol)
                        G.check(file, id, "poke.mine", G.bool(e, "mine"), item.isMine)
                    }
                    is MessagesConversationItem.pending -> G.check(file, id, "item.kind", e.string("kind"), "pending")
                }
            }
        }
    }

    @Test
    fun storeRulesMatchSwift() {
        val file = Golden.load("messages/store-rules")
        val seen = HashSet<String>()
        var handled = 0
        for (c in file.cases) {
            val id = c.string("id")
            when {
                id.startsWith("badge-") -> {
                    val entries = G.entries(c, "entries")
                    val serverOrder = G.pairs(c["serverOrder"])
                    val historySnapshot = G.optInt(c, "historySerial")?.let { MessageHistoryReadSnapshot(it, serverOrder) }
                    val summary = (c["summary"] as? JsonObject)?.let { s ->
                        MessagesSummarySnapshot(
                            s.int("serial"),
                            MessageUnreadSummary(0, s.array("peers").map { p ->
                                val o = p.jsonObject
                                MessageUnreadPeer(o.string("peer"), o.int("count").toLong(), null)
                            }),
                        )
                    }
                    val optimistic = G.optimistic(c, "optimistic")
                    val stamps = c.array("legacyStamps").associate { s -> s.jsonObject.string("peer") to s.jsonObject.bits("atBits") }
                    G.check(file, id, "unreadCount", c.int("unreadCount"),
                        MessagesBadgeRules.unreadCount(entries, historySnapshot, summary, optimistic, stamps))
                    G.check(file, id, "countsByPeer", G.pairs(c["countsByPeer"]),
                        MessagesBadgeRules.unreadCountsByPeer(entries, historySnapshot, summary, optimistic, stamps))
                    seen += "badge"
                }
                id.startsWith("pending-") -> {
                    val pending = G.pending(c, "pending", peerOf = { it.string("peer") }, createdAt = { G.date(it, "createdAtBits") })
                    val kept = MessagesPendingRules.reconcile(pending, G.set(c, "previous"), G.entries(c, "applied"), c.int("appliedSerial"))
                    G.check(file, id, "kept", G.strings(c, "kept"), kept.map { it.id })
                    seen += "pending"
                }
                id == "text" -> {
                    checkText(file, c)
                    seen += "text"
                }
                id == "times" -> {
                    for (t in c.array("times")) {
                        val o = t.jsonObject
                        val date = G.date(o, "dateBits")
                        val now = G.date(o, "nowBits")
                        G.check(file, id, "timeText $o", o.string("text"), MessagesListRules.timeText(date, now, kst))
                        G.check(file, id, "relative $o", o.string("relative"), MobileRelativeTime.text(date, now, kst))
                        G.check(file, id, "blockedAt $o", o.string("blockedAt"), BlockReportText.blockedAtLine(date, now))
                    }
                    seen += "times"
                }
                id.startsWith("presence-") -> {
                    checkPresence(file, id, c)
                    seen += "presence"
                }
                // 모르는 접두는 조용히 건너뛰지 않는다 — 생성기가 id 를 바꾸면 그 케이스를 아무도 대조하지 않게 된다(검증 V14).
                else -> fail("모르는 case id: $id (store-rules 는 badge-* · pending-* · text · times · presence-* 만)")
            }
            handled += 1
        }
        assertEquals(file.cases.size, handled, "대조하지 않은 케이스가 있다")
        assertEquals(setOf("badge", "pending", "text", "times", "presence"), seen.toSet(), "골든 갈래가 빠졌다")
    }

    private fun checkText(file: GoldenFile, c: JsonObject) {
        val id = "text"
        for (p in c.array("previews")) {
            val o = p.jsonObject
            G.check(file, id, "preview(${o.string("body")})", o.string("preview"), MessagesListRules.preview(o.string("body")))
        }
        for (p in c.array("counters")) {
            val o = p.jsonObject
            val draft = o.string("draft")
            G.check(file, id, "counter(${draft.length})", G.optString(o, "counter"), MessagesComposerRules.counterText(draft))
            G.check(file, id, "overflow(${draft.length})", G.bool(o, "overflow"), MessagesComposerRules.isOverflowing(draft))
        }
        for (p in c.array("countBadges")) {
            val o = p.jsonObject
            G.check(file, id, "countBadge $o", G.optString(o, "badge"), MessagesListRules.countBadge(G.bool(o, "unread"), G.optInt(o, "count")))
        }
        for (p in c.array("subtitles")) {
            val o = p.jsonObject
            G.check(file, id, "subtitle $o", G.optString(o, "subtitle"), MessagesListRules.subtitle(o.int("count")))
        }
        val outcomes = mapOf(
            "ok" to MessageSendOutcome.Ok, "notWorking" to MessageSendOutcome.NotWorking, "targetNotWorking" to MessageSendOutcome.TargetNotWorking,
            "targetFocused" to MessageSendOutcome.TargetFocused, "tooLong" to MessageSendOutcome.TooLong, "notText" to MessageSendOutcome.NotText,
            "blackout" to MessageSendOutcome.Blackout, "flood" to MessageSendOutcome.Flood, "invalid" to MessageSendOutcome.Invalid,
        )
        for (p in c.array("notices")) {
            val o = p.jsonObject
            val outcome = outcomes[o.string("outcome")] ?: error("모르는 결과 ${o.string("outcome")}")
            G.check(file, id, "notice $o", G.optString(o, "notice"), MessagesSendRules.notice(outcome, G.optInt(o, "max")?.toLong()))
        }
        G.check(file, id, "connectionNotice", c.string("connectionNotice"), MessagesSendRules.connectionNotice)
        for (p in c.array("headers")) {
            val o = p.jsonObject
            val h = MessagesConversationRules.header(G.optString(o, "name"), G.bool(o, "resolving"))
            G.check(file, id, "header.title $o", o.string("title"), h.title)
            G.check(file, id, "header.avatar $o", G.optString(o, "avatarName"), h.avatarName)
            G.check(file, id, "header.a11y $o", o.string("a11y"), h.accessibilityLabel)
        }
        for (p in c.array("empty")) {
            val o = p.jsonObject
            val e = MessagesConversationRules.emptyState(G.bool(o, "loaded"), G.bool(o, "failed"))
            G.check(file, id, "empty $o", MessagesEmptyState(o.string("symbol"), o.string("title"), G.optString(o, "hint"), G.bool(o, "retry")), e)
        }
    }

    private fun checkPresence(file: GoldenFile, id: String, c: JsonObject) {
        val messagesDirectory = (c["messagesDirectory"] as? JsonArray)?.map {
            val o = it.jsonObject
            PokeDirectoryEntry(
                userID = o.string("id"), name = o.string("name"), avatarURL = SwiftURL.parse(G.optString(o, "avatar")),
                isWorking = G.bool(o, "working"), center = G.optString(o, "center"), statusMessage = G.optString(o, "status"),
            )
        }
        val nowDirectory = (c["nowDirectory"] as? JsonArray)?.map {
            val o = it.jsonObject
            PokeDirectoryRow(
                userId = o.string("id"), displayName = o.string("name"), avatarUrl = G.optString(o, "avatar"), isWorking = G.bool(o, "working"),
                center = G.optString(o, "center"), statusMessage = G.optString(o, "status"),
            )
        }
        val working = c.array("nowWorking").map {
            val o = it.jsonObject
            MessagesPresenceRules.Working(o.string("id"), o.string("name"), SwiftURL.parse(G.optString(o, "avatar")), G.optString(o, "center"), G.bool(o, "stale"))
        }
        val board = MessagesPresenceRules.board(working, G.set(c, "teamIDs"), nowDirectory, messagesDirectory, G.optString(c, "me"), NaturalKoNameCollation)
        G.check(file, id, "isKnown", G.bool(c, "isKnown"), board.isKnown)
        val peers = c.array("peers").map { it.jsonObject }
        G.check(file, id, "peers.ids", peers.map { it.string("id") }.toSet(), board.peers.keys)
        for (p in peers) {
            val presence = board.peers.getValue(p.string("id"))
            G.check(file, id, "peer.status ${p.string("id")}", p.string("status"), presence.status.rawValue)
            G.check(file, id, "peer.center ${p.string("id")}", G.optString(p, "center"), presence.center)
            G.check(file, id, "peer.headerLine ${p.string("id")}", G.optString(p, "headerLine"), MessagesPresenceRules.headerLine(presence))
        }
        val boardWorking = c.array("boardWorking").map { it.jsonObject }
        G.check(file, id, "working.ids", boardWorking.map { it.string("id") }, board.working.map { it.id })
        for ((person, e) in board.working.zip(boardWorking)) {
            G.check(file, id, "working.name", e.string("name"), person.name)
            G.check(file, id, "working.avatar", G.optString(e, "avatar"), person.avatarURL?.absoluteString)
            G.check(file, id, "working.status", e.string("status"), person.status.rawValue)
            G.check(file, id, "working.center", G.optString(e, "center"), person.center)
        }
        G.check(file, id, "statuses", c.array("statuses").associate { it.jsonObject.string("id") to it.jsonObject.string("text") }, board.statuses)
        G.check(file, id, "workingPeerIDs", G.set(c, "workingPeerIDs"), MessagesSortRules.workingPeerIDs(board))
    }
}
