// 원본: Sources/CheckCore/MessageRules.swift @ 1b8260d (안내 문구 · 읽음 규칙 · 정렬 · 대화 묶음 · 날짜 구분선)
package com.yehsung.aingcheck.core.rules.text

import kotlin.time.Instant
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime

/*
 * 메시지의 순수 규칙 — 맥 · 폰 · Android · Windows 메시지 화면이 같은 묶기 · 정렬 · 날짜 구분선 · 안 읽음 판정 · 안내 문구를 쓴다.
 *
 * 이력 한 줄은 전선 타입(W1-d `MessageHistoryEntry`)이고 rules 는 그 갈래를 부를 수 없다(의존 rules → wire, 아직 없음). 그래서 규칙은
 * [MessageEntryFacts] 를 받는 **제네릭**이다 — 호출부(메시지 스토어 W2-b)가 전선 행을 이 인터페이스로 감싸 넘기고, 돌려받는 목록은
 * 같은 타입 그대로다. 시각은 1970 기준 초(Swift Date).
 */

/** 서버 status 의 사람 말 번역 · 창 상수. */
object MessageNoticeText {
    /** 이력 조회 창(시간). 서버 message_retention_hours() 와 같은 값(24). */
    const val historyHours = 24
    /** 한 번에 받아 올 이력 건수(서버가 1~500 으로 접는다). */
    const val historyLimit = 200
    const val sent = "메시지를 보냈어요"
    const val notWorking = "근무 중일 때만 메시지를 보낼 수 있어요"
    const val targetNotWorking = "자리비움 상태에는 보낼 수 없어요"
    const val targetFocused = "지금 집중 중이에요. 나중에 보내 주세요"
    const val notText = "보낼 수 없는 글자가 섞여 있어요"
    const val blackout = "지금은 메시지를 주고받을 수 없어요"
    const val invalid = "지금은 메시지를 보낼 수 없어요. 잠시 후 다시 시도해 주세요"
    fun tooLong(maxLength: Int? = null): String = "메시지는 ${maxLength ?: MessageBody.maxLength}자까지예요. 줄여서 보내 주세요"
    val expiry: String get() = "${historyHours}시간이 지난 메시지는 사라져요"
}

/** 규칙이 읽는 이력 한 줄의 사실(전선 `MessageHistoryEntry` 의 투영). */
interface MessageEntryFacts {
    val id: String
    val peerUserID: String
    val peerName: String
    val peerAvatarURL: String?
    val isMine: Boolean
    /** 서버 기준 안 읽음(받은 것만 의미 있음). 읽음 기능을 모르는 응답이면 null. */
    val isUnread: Boolean?
    /** 1970 기준 초. */
    val createdAt: Double
}

/** 이력 한 번의 결과. entries 는 **서버 순서 그대로**다. */
data class MessageHistoryLoad<E : MessageEntryFacts>(val entries: List<E>, val hasReadReceipts: Boolean) {
    /** 메시지 id → 서버 응답 안의 자리(0부터, 같은 id 는 처음 자리). */
    val serverOrder: Map<String, Int>
        get() {
            val order = LinkedHashMap<String, Int>()
            entries.forEachIndexed { index, entry -> if (entry.id !in order) order[entry.id] = index }
            return order
        }
}

data class MessageHistoryReadSnapshot(val serial: Int, val serverOrder: Map<String, Int>)

/** 안 읽음 요약 한 번의 사실(전선 `MessageUnreadSummary` 는 상대 id 집합만 쓴다). */
data class MessageUnreadSummarySnapshot(val serial: Int, val unreadPeerIDs: Set<String>)

/** 상대 하나에 대한 낙관 읽음 — "이 id 까지 읽었다고 서버에 말했다(또는 말하는 중이다)". */
data class MessageOptimisticRead(
    val throughID: String,
    val recordedSerial: Int,
    val settledSerial: Int? = null,
    val failed: Boolean = false,
) {
    /** 일련번호 [serial] 로 띄운 서버 조회가 이 기록을 이미 반영한 서버 상태를 봤는가(정산 뒤에 띄운 조회만). */
    fun isKnown(serial: Int): Boolean {
        val settled = settledSerial ?: return false
        return serial > settled
    }
}

/** 안 읽음 · 읽음 경계 · 말풍선 필터의 순수 규칙. */
object MessageUnreadRules {
    fun <E : MessageEntryFacts> unreadPeerIDs(
        history: List<E>,
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessageUnreadSummarySnapshot?,
        optimistic: Map<String, MessageOptimisticRead>,
        legacyStamps: Map<String, Double>,
    ): Set<String> {
        val useHistory = when {
            historySnapshot == null && summary == null -> return legacyUnreadPeerIDs(history, legacyStamps)
            summary == null -> true
            historySnapshot == null -> false
            else -> historySnapshot.serial > summary.serial
        }
        if (useHistory && historySnapshot != null) {
            val order = effectiveOrder(history, historySnapshot.serverOrder)
            val peers = LinkedHashSet<String>()
            for (entry in history) {
                if (entry.isMine || entry.isUnread != true) continue
                val record = optimistic[entry.peerUserID]
                if (record != null && !record.isKnown(historySnapshot.serial) && isCovered(entry, record, order)) continue
                peers += entry.peerUserID
            }
            return peers
        }
        summary ?: return emptySet()
        val peers = LinkedHashSet(summary.unreadPeerIDs)
        for ((peer, record) in optimistic) if (!record.isKnown(summary.serial)) peers.remove(peer)
        return peers
    }

    /** 옛 규칙: 받은 것의 마지막 시각 > 내가 그 대화를 마지막으로 연 시각(도장 없음 = 안 읽음). */
    fun <E : MessageEntryFacts> legacyUnreadPeerIDs(history: List<E>, stamps: Map<String, Double>): Set<String> {
        val unread = LinkedHashSet<String>()
        for (thread in MessageThreadBuilder.threads(history)) {
            val lastIncoming = thread.messages.lastOrNull { !it.isMine } ?: continue
            val stamp = stamps[thread.peerUserID]
            if (stamp != null && lastIncoming.createdAt <= stamp) continue
            unread += thread.peerUserID
        }
        return unread
    }

    /** 읽음을 올릴 경계(그 대화의 마지막 받은 메시지 id, 서버 순서 기준). 올릴 것이 없으면 null. */
    fun <E : MessageEntryFacts> markTarget(
        peer: String,
        history: List<E>,
        snapshot: MessageHistoryReadSnapshot,
        optimistic: MessageOptimisticRead?,
    ): String? {
        val received = history.withIndex().filter { it.value.peerUserID == peer && !it.value.isMine }
        if (received.none { it.value.isUnread == true }) return null
        val order = effectiveOrder(history, snapshot.serverOrder)
        // Swift `max(by:)` — 같으면 앞의 것을 둔다(여기선 자리(offset)까지 보므로 같은 일이 없다).
        var best: IndexedValue<E>? = null
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

    /** 말풍선으로 띄우지 않을 받은 메시지인가(서버 기준 읽음 · 낙관 읽음으로 덮임 · 더 나중 요약이 그 상대를 안 읽음에 안 둠). */
    fun <E : MessageEntryFacts> isAlreadyRead(
        messageID: String,
        history: List<E>,
        snapshot: MessageHistoryReadSnapshot?,
        optimistic: Map<String, MessageOptimisticRead>,
        summary: MessageUnreadSummarySnapshot? = null,
    ): Boolean {
        snapshot ?: return false
        val entry = history.firstOrNull { it.id == messageID } ?: return false
        if (entry.isMine) return false
        if (entry.isUnread == false) return true
        val record = optimistic[entry.peerUserID]
        if (record != null && isCovered(entry, record, effectiveOrder(history, snapshot.serverOrder))) return true
        if (summary != null && summary.serial > snapshot.serial && entry.peerUserID !in summary.unreadPeerIDs) return true
        return false
    }

    /** 서버 순서 + 이력에 있지만 서버 순서가 모르는 id(즉시 삽입한 도착분)를 그 뒤에 이력 자리 순으로. */
    fun <E : MessageEntryFacts> effectiveOrder(history: List<E>, serverOrder: Map<String, Int>): Map<String, Int> {
        if (history.none { it.id !in serverOrder }) return serverOrder
        val order = LinkedHashMap(serverOrder)
        var next = (serverOrder.values.maxOrNull() ?: -1) + 1
        for (entry in history) {
            if (entry.id !in order) {
                order[entry.id] = next
                next += 1
            }
        }
        return order
    }

    /** 받은 메시지가 낙관 읽음 경계 안쪽(경계 자신 포함)인가. 순서표에서 못 찾으면 덮이지 않음. */
    fun isCovered(entry: MessageEntryFacts, record: MessageOptimisticRead, order: Map<String, Int>): Boolean {
        if (entry.id == record.throughID) return true
        val through = order[record.throughID] ?: return false
        val index = order[entry.id] ?: return false
        return index <= through
    }
}

/**
 * 서버 정렬을 신뢰하지 않고 다시 세운다: 오래된 것 → 최신, 같은 초면 서버 순서, 그다음 도착 순서, 그다음 id.
 *
 * INV-MessageRules-f33cc83d 이식: **서버 순서** — createdAt 은 created_epoch(초, 반올림)이라 같은 초 안에서 오간 말이 동률이다. 동률을 id 사전순으로
 * 깨면 답장이 질문보다 위에 그려진다(X1). 서버는 created_at(마이크로초) 순서로 주므로 serverOrder(응답 안의 자리)가 그 선후다. 순서표에 없는 id 는
 * 맨 뒤(Int.MAX_VALUE)로 보내 비교가 언제나 전순서가 되게 한다.
 * INV-MessageRules-e90c753b 이식: **도착 순서** — 서버 순서가 모르는 즉시 삽입분(take_pokes 가 들고 온 말)끼리의 같은 초 동률은 id 가 아니라
 * arrivalOrder(삽입 번호)로 깬다. 표에 없으면 -1(서버가 아는 말보다 늦게 왔다 = 같은 초의 다른 말 뒤). 키는 (초, 서버 자리, 도착 번호, id) 사전식.
 * id 비교는 Swift String `<`(유니코드 스칼라 순 — uuid 는 ASCII 라 UTF-16 순과 같다).
 */
fun <E : MessageEntryFacts> List<E>.sortedForMessageHistory(
    serverOrder: Map<String, Int>? = null,
    arrivalOrder: Map<String, Int> = emptyMap(),
): List<E> = sortedWith { lhs, rhs ->
    if (lhs.createdAt != rhs.createdAt) return@sortedWith if (lhs.createdAt < rhs.createdAt) -1 else 1
    if (serverOrder != null) {
        val l = serverOrder[lhs.id] ?: Int.MAX_VALUE
        val r = serverOrder[rhs.id] ?: Int.MAX_VALUE
        if (l != r) return@sortedWith l.compareTo(r)
    }
    val la = arrivalOrder[lhs.id] ?: -1
    val ra = arrivalOrder[rhs.id] ?: -1
    if (la != ra) return@sortedWith la.compareTo(ra)
    swiftStringCompare(lhs.id, rhs.id)
}

/** Swift `String <` — 정준 동치(NFC)로 접은 뒤 유니코드 스칼라 값 순(uuid 는 ASCII 라 그대로다). */
internal fun swiftStringCompare(a: String, b: String): Int {
    val x = TextNormalization.nfc(a).codePointArray()
    val y = TextNormalization.nfc(b).codePointArray()
    for (i in 0 until minOf(x.size, y.size)) if (x[i] != y[i]) return x[i].compareTo(y[i])
    return x.size.compareTo(y.size)
}

/** 한 사람과의 대화. messages 는 시간순(오래된 것 → 최신). */
data class MessageThread<E : MessageEntryFacts>(
    val peerUserID: String,
    val peerName: String,
    val peerAvatarURL: String?,
    val messages: List<E>,
) {
    val id: String get() = peerUserID
    val lastMessage: E? get() = messages.lastOrNull()
}

/** 대화 화면 한 줄 — 날짜 구분선이 말풍선과 같은 배열에 산다. */
sealed interface MessageTimelineItem<out E : MessageEntryFacts> {
    val id: String

    data class day(val key: String, val label: String) : MessageTimelineItem<Nothing> {
        override val id: String get() = "day-$key"
    }

    data class bubble<E : MessageEntryFacts>(val entry: E) : MessageTimelineItem<E> {
        override val id: String get() = entry.id
    }
}

/**
 * 이력 → 화면 구조. 달력은 **기기 시간대**다(Swift `Calendar.current` — 메시지 날짜 구분선 · 시각은 KST 고정이 아니다).
 * Android · Windows 는 `TimeZone.currentSystemDefault()` 를 넘긴다. 그레고리력만 쓴다(24시간 창이라 다른 달력 체계의 연도는 키 동일성에만 든다).
 */
object MessageThreadBuilder {
    /** 상대별로 묶는다. 각 대화는 시간순, 대화 목록은 최근 대화순. 이름 · 아바타는 가장 최근 행의 것. */
    fun <E : MessageEntryFacts> threads(
        entries: List<E>,
        serverOrder: Map<String, Int>? = null,
        arrivalOrder: Map<String, Int> = emptyMap(),
    ): List<MessageThread<E>> {
        val order = ArrayList<String>()
        val grouped = HashMap<String, MutableList<E>>()
        for (entry in entries.sortedForMessageHistory(serverOrder, arrivalOrder)) {
            val bucket = grouped[entry.peerUserID]
            if (bucket == null) {
                order += entry.peerUserID
                grouped[entry.peerUserID] = mutableListOf(entry)
            } else {
                bucket += entry
            }
        }
        val threads = order.mapNotNull { peer ->
            val messages = grouped[peer] ?: return@mapNotNull null
            val latest = messages.lastOrNull() ?: return@mapNotNull null
            MessageThread(peer, latest.peerName, latest.peerAvatarURL, messages.toList())
        }
        return threads.sortedWith { lhs, rhs ->
            val l = lhs.lastMessage?.createdAt ?: Double.NEGATIVE_INFINITY
            val r = rhs.lastMessage?.createdAt ?: Double.NEGATIVE_INFINITY
            if (l != r) return@sortedWith if (l > r) -1 else 1
            swiftStringCompare(lhs.peerUserID, rhs.peerUserID)
        }
    }

    /** 시간순 말풍선 사이에 날짜 구분선을 끼운다. 첫 항목 앞에도 반드시 하나 선다. */
    fun <E : MessageEntryFacts> timeline(messages: List<E>, now: Double, zone: TimeZone): List<MessageTimelineItem<E>> {
        val items = ArrayList<MessageTimelineItem<E>>()
        var lastKey: String? = null
        for (entry in messages) {
            val key = dayKey(entry.createdAt, zone)
            if (key != lastKey) {
                items += MessageTimelineItem.day(key, dayLabel(entry.createdAt, now, zone))
                lastKey = key
            }
            items += MessageTimelineItem.bubble(entry)
        }
        return items
    }

    private fun localDate(seconds: Double, zone: TimeZone): LocalDate = instantOf(seconds).toLocalDateTime(zone).date

    private fun instantOf(seconds: Double): Instant {
        val whole = kotlin.math.floor(seconds)
        val nanos = ((seconds - whole) * 1e9).toLong().coerceIn(0, 999_999_999)
        return Instant.fromEpochSeconds(whole.toLong(), nanos)
    }

    /** 날짜 구분선의 동일성 키 'y-M-d'(자리 채움 없음 — "2026-9-8"). 구분선 id 로 그대로 쓴다. */
    fun dayKey(date: Double, zone: TimeZone): String {
        val d = localDate(date, zone)
        return "${d.year}-${d.month.ordinal + 1}-${d.day}"
    }

    /** "오늘" / "어제" / "M월 d일". */
    fun dayLabel(date: Double, now: Double, zone: TimeZone): String {
        val day = localDate(date, zone)
        val today = localDate(now, zone)
        if (day == today) return "오늘"
        if (day == today.minus(DatePeriod(days = 1))) return "어제"
        return "${day.month.ordinal + 1}월 ${day.day}일"
    }

    /** 말풍선 옆 시각("14:05") — 24시간제로 못 박는다. */
    fun clockText(date: Double, zone: TimeZone): String {
        val t = instantOf(date).toLocalDateTime(zone)
        return "${t.hour.toString().padStart(2, '0')}:${t.minute.toString().padStart(2, '0')}"
    }

    // INV-MessageRules-96824842 이식: `listStampText` · `previewText` 는 v0.2.50 에 왼쪽 대화 목록과 함께 사라졌다 — 옮기지 않는다(죽은 가지를 되살리지
    // 않는다). 되살릴 날이 오면 dayLabel · clockText 위에 다시 세운다.
}
