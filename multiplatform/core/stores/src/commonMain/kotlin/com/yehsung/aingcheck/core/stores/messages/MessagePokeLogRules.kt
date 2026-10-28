// 원본: Sources/CheckCore/MessagePokeLog.swift:314-526(MessagePokeLogRules · MessageConversationLine · MessageConversationTimeline · MessagePokeLogText) @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageHistoryReadSnapshot
import com.yehsung.aingcheck.core.rules.text.MessageOptimisticRead
import com.yehsung.aingcheck.core.rules.text.MessageThreadBuilder
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogKind
import kotlinx.datetime.TimeZone

/*
 * 대화창 찌르기 기록의 순수 규칙(v0.3.65). 전선 모양·디코드·`microsecondsSinceEpoch` 는 W1-d(core/wire · core/net)가 옮겼다 —
 * 여기는 안 읽음 · 경계 · 표시 순서 · 대화 줄 끼워 넣기 · 문구다.
 *
 * Swift 머리 ② "메시지 규칙과 섞지 않는다" — 찌르기는 메시지 이력에 들어가지 않는다(경계·배지·말풍선 필터가 찌르기 id 를 메시지로
 * 오인하는 길을 타입으로 닫는다). 그래서 메시지 규칙(W1-c `MessageUnreadRules`)과 같은 모양의 함수를 여기 따로 둔다.
 */
object MessagePokeLogRules {
    /**
     * 선후 판정의 순서표: 서버 순서 + **서버 순서가 모르는 id**(즉시 넣은 찌르기)를 그 뒤에 기록 자리 순으로.
     * `MessageUnreadRules.effectiveOrder` 와 같은 규칙이다(그쪽은 메시지 타입을 받아 여기서 따로 둔다).
     */
    fun effectiveOrder(log: List<MessagePokeLogEntry>, serverOrder: Map<String, Int>): Map<String, Int> {
        if (log.none { it.id !in serverOrder }) return serverOrder
        val order = LinkedHashMap(serverOrder)
        var next = (serverOrder.values.maxOrNull() ?: -1) + 1
        for (entry in log) {
            if (entry.id !in order) {
                order[entry.id] = next
                next += 1
            }
        }
        return order
    }

    /** 받은 찌르기가 낙관 읽음 경계 **안쪽**(경계 자신 포함)인가. 경계·그 찌르기를 순서표에서 못 찾으면 덮이지 않았다. */
    fun isCovered(entry: MessagePokeLogEntry, record: MessageOptimisticRead, order: Map<String, Int>): Boolean {
        if (entry.id == record.throughID) return true
        val through = order[record.throughID] ?: return false
        val index = order[entry.id] ?: return false
        return index <= through
    }

    /**
     * 안 본 찌르기가 있는 상대들. 서버 플래그(`isUnread == true`)에서 **그 스냅샷이 모르는 낙관 읽음**을 뺀다
     * (`MessageUnreadRules.unreadPeerIDs` 의 이력 갈래와 같은 규칙 — 찌르기에는 요약 RPC 가 없다).
     */
    fun unreadPeerIDs(
        log: List<MessagePokeLogEntry>,
        snapshot: MessageHistoryReadSnapshot,
        optimistic: Map<String, MessageOptimisticRead>,
    ): Set<String> {
        val order = effectiveOrder(log, snapshot.serverOrder)
        val peers = LinkedHashSet<String>()
        for (entry in log) {
            if (entry.isMine || entry.isUnread != true) continue
            val record = optimistic[entry.peerUserID]
            if (record != null && !record.isKnown(snapshot.serial) && isCovered(entry, record, order)) continue
            peers += entry.peerUserID
        }
        return peers
    }

    /**
     * 찌르기 읽음 경계 = 그 대화의 **마지막 받은 찌르기 id**(서버 순서 기준 — 화면에 보인 마지막 것). 올릴 것이 없으면 null.
     *  · 서버 기준 안 본 받은 찌르기가 없으면 null.
     *  · 같은 경계로 이미 올렸거나 올리는 중이면 null — 실패로 정산된 기록만 다시 올린다(`MessageUnreadRules.markTarget` 과 같다).
     */
    fun markTarget(
        peer: String,
        log: List<MessagePokeLogEntry>,
        snapshot: MessageHistoryReadSnapshot,
        optimistic: MessageOptimisticRead?,
    ): String? {
        val received = log.withIndex().filter { it.value.peerUserID == peer && !it.value.isMine }
        if (received.none { it.value.isUnread == true }) return null
        val order = effectiveOrder(log, snapshot.serverOrder)
        // Swift `max(by:)` — 같으면 뒤의 것이 이긴다. 여기서는 자리(offset)까지 보므로 같은 일이 없다.
        var best: IndexedValue<MessagePokeLogEntry>? = null
        for (candidate in received) {
            val current = best
            if (current == null) {
                best = candidate
                continue
            }
            val l = order[current.value.id] ?: -1
            val r = order[candidate.value.id] ?: -1
            val increasing = if (l != r) l < r else current.index < candidate.index
            if (increasing) best = candidate
        }
        val last = best?.value ?: return null
        if (optimistic != null && optimistic.throughID == last.id && !optimistic.failed) return null
        return last.id
    }

    /** 기록을 표시 순서로(오래된 것 → 최신): 초 → 서버 시각 순위 → 도착 순서 → id(Swift String `<`). */
    fun sorted(
        log: List<MessagePokeLogEntry>,
        chronology: Map<String, Int>,
        arrivalOrder: Map<String, Int> = emptyMap(),
    ): List<MessagePokeLogEntry> = log.sortedWith { lhs, rhs ->
        if (lhs.createdAt != rhs.createdAt) return@sortedWith lhs.createdAt.compareTo(rhs.createdAt)
        val l = chronology[lhs.id] ?: Int.MAX_VALUE
        val r = chronology[rhs.id] ?: Int.MAX_VALUE
        if (l != r) return@sortedWith l.compareTo(r)
        val la = arrivalOrder[lhs.id] ?: -1
        val ra = arrivalOrder[rhs.id] ?: -1
        if (la != ra) return@sortedWith la.compareTo(ra)
        SwiftStrings.compare(lhs.id, rhs.id)
    }
}

/**
 * 대화 화면 한 줄(v0.3.65). W1-c `MessageTimelineItem` 에 찌르기 줄을 더한 모양이다. 찌르기가 없으면
 * `MessageThreadBuilder.timeline` 과 **줄 단위로 같다**.
 */
sealed interface MessageConversationLine {
    val id: String

    /** 스크롤 따라가기의 "마지막 줄이 내 것인가". */
    val isMine: Boolean

    data class day(val key: String, val label: String) : MessageConversationLine {
        override val id: String get() = "day-$key"
        override val isMine: Boolean get() = false
    }

    data class bubble(val entry: MessageEntry) : MessageConversationLine {
        override val id: String get() = entry.id
        override val isMine: Boolean get() = entry.isMine
    }

    data class poke(val entry: MessagePokeLogEntry) : MessageConversationLine {
        override val id: String get() = "poke-${entry.id}"
        override val isMine: Boolean get() = entry.isMine
    }
}

object MessageConversationTimeline {
    /**
     * 시간순 메시지(이미 대화 순서) 사이에 시간순 찌르기를 **끼워 넣고** 날짜 구분선을 세운다.
     *
     * 메시지끼리 · 찌르기끼리의 순서는 **건드리지 않는다**(안정 병합) — 메시지 순서는 이미 같은 초 동률까지 깨진 대화 순서다.
     * 병합이 정하는 것은 둘 사이의 끼움 자리뿐이다: 초가 다르면 초, 같은 초면 서버 시각 순위(`chronology`), 순위를 모르는 쪽
     * (서버가 아직 모르는 즉시 삽입분)은 아는 쪽 **뒤**, 둘 다 모르면 메시지가 먼저다(결정성).
     * 달력은 **넘긴다**(Swift 기본값 `.current` 자리 — 폰 메시지 화면은 KST, [MessagesTime.kst]).
     */
    fun lines(
        messages: List<MessageEntry>,
        pokes: List<MessagePokeLogEntry>,
        chronology: Map<String, Int> = emptyMap(),
        now: Double,
        zone: TimeZone,
    ): List<MessageConversationLine> {
        val merged = ArrayList<MessageConversationLine>(messages.size + pokes.size)
        var m = 0
        var p = 0
        while (m < messages.size || p < pokes.size) {
            if (p < pokes.size && (m >= messages.size || pokeGoesFirst(pokes[p], messages[m], chronology))) {
                merged += MessageConversationLine.poke(pokes[p])
                p += 1
            } else {
                merged += MessageConversationLine.bubble(messages[m])
                m += 1
            }
        }
        val lines = ArrayList<MessageConversationLine>(merged.size + 2)
        var lastKey: String? = null
        for (line in merged) {
            val date = when (line) {
                is MessageConversationLine.bubble -> line.entry.createdAt
                is MessageConversationLine.poke -> line.entry.createdAt.timeIntervalSince1970
                is MessageConversationLine.day -> continue
            }
            val key = MessageThreadBuilder.dayKey(date, zone)
            if (key != lastKey) {
                lines += MessageConversationLine.day(key, MessageThreadBuilder.dayLabel(date, now, zone))
                lastKey = key
            }
            lines += line
        }
        return lines
    }

    private fun pokeGoesFirst(poke: MessagePokeLogEntry, message: MessageEntry, chronology: Map<String, Int>): Boolean {
        // Swift `Date` 비교 그대로(2001 기준 값 — 1970 값으로 바꿔 견주면 끝자리 반올림이 갈릴 수 있다).
        if (poke.createdAt != message.createdDate) return poke.createdAt < message.createdDate
        val p = chronology[poke.id]
        val m = chronology[message.id]
        return when {
            p != null && m != null -> p < m
            p != null -> true
            else -> false
        }
    }
}

/**
 * 찌르기 줄의 글자(v0.3.65). 말투는 캐릭터 말풍선("○○님이 콕 찔렀어요!")을 따르고, 시각은 말풍선 옆 시각과 **같은 눈금**
 * (`MessageThreadBuilder.clockText` — 24시간제)이다. 맥과 한 벌이다.
 */
object MessagePokeLogText {
    /** 아이콘 — 레일 [콕] 손가락과 울트라 번개(SF Symbols 이름 그대로 — 화면 층이 Material Symbols 로 바꾼다, §8-1 D§13-3). */
    fun symbol(kind: MessagePokeLogKind): String = when (kind) {
        MessagePokeLogKind.poke -> "hand.point.right.fill"
        MessagePokeLogKind.ultra -> "bolt.fill"
    }

    /** 주어("○○님이" / "내가"). 이름이 길면 이 부분만 줄인다(시각은 언제나 보인다). */
    fun subject(entry: MessagePokeLogEntry): String = if (entry.isMine) "내가" else "${entry.peerName}님이"

    /** 술어 + 시각("콕 찔렀어요 · 15:12"). */
    fun predicate(entry: MessagePokeLogEntry, zone: TimeZone): String {
        val verb = if (entry.kind == MessagePokeLogKind.ultra) "울트라 찔렀어요" else "콕 찔렀어요"
        return "$verb · ${MessageThreadBuilder.clockText(entry.createdAt.timeIntervalSince1970, zone)}"
    }

    /** 한 줄 전체(보이스오버 · 시험). */
    fun line(entry: MessagePokeLogEntry, zone: TimeZone): String = "${subject(entry)} ${predicate(entry, zone)}"
}
