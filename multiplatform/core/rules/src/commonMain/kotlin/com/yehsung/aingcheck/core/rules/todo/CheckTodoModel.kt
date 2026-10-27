// 원본: Sources/CheckCore/CheckTodoModel.swift @ 1b8260d (항목 · 파일 상태 · TodoRules · mergedSync — 파일 저장소 TodoFileStore 와
//       @MainActor 스토어 TodoListStore 는 파일 I/O · 관찰 상태라 지금/할 일 스토어 갈래(W2)가 이 규칙 위에 옮긴다)
package com.yehsung.aingcheck.core.rules.todo

import com.yehsung.aingcheck.core.rules.format.SwiftDate
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.insights.MilestoneTracker
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.TextNormalization
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.text.codePointArray
import com.yehsung.aingcheck.core.rules.text.codePointCountCompat
import com.yehsung.aingcheck.core.rules.text.stringFromCodePoints

/**
 * 할 일 한 줄(v0.3.30 부터 계정에 저장돼 기기끼리 맞춰진다 — 서버 `todo_items` · `todo_sync`).
 * INV-CheckTodoModel-f1b4dd4f 이식: **모든 시각은 정수 밀리초에서 만든 값이다**([TodoRules.milliseconds] · [TodoRules.date]) —
 * 소수 ms 가 남으면 "보낸 값 == 지금 값" 판정이 반올림 한 번에 흔들린다.
 * id 는 **소문자 uuid 글자**(Swift UUID 는 대문자로 찍히지만 서버·전선은 소문자 — 정렬은 대문자 글자 순과 같다).
 * 시각은 1970 기준 초 Double(Swift Date).
 */
data class TodoItem(
    val id: String,
    val title: String,
    val createdAt: Double,
    val updatedAt: Double,
    val completedAt: Double? = null,
    val deletedAt: Double? = null,
    /** 처음 만든 날의 KST yyyyMMdd — 이월 배지의 기준(완료/수정으로 흔들리지 않는다). */
    val originDayKey: String,
) {
    val isDone: Boolean get() = completedAt != null

    /** 서버 LWW 가 비교하는 값. */
    val updatedAtMs: Long get() = TodoRules.milliseconds(updatedAt)

    /** 네 시각을 정수 ms 격자에 올린 사본(1세대 파일을 읽을 때). */
    fun withMillisecondTimes(): TodoItem = copy(
        createdAt = TodoRules.normalizedTime(createdAt),
        updatedAt = TodoRules.normalizedTime(updatedAt),
        completedAt = completedAt?.let(TodoRules::normalizedTime),
        deletedAt = deletedAt?.let(TodoRules::normalizedTime),
    )
}

/** 파일에 실리는 동기화 상태(watermark · 보낼 것 · 붙잡기). */
data class TodoFileSyncState(val watermarkMs: Long?, val pendingIDs: List<String>, val heldRejectedIDs: List<String> = emptyList())

/** 파일 전체(2세대). sync 를 모르면 **모든 항목이 보낼 것**이다. */
data class TodoFile(val version: Int = CURRENT_VERSION, val items: List<TodoItem>, val sync: TodoFileSyncState = TodoFileSyncState(null, items.map { it.id })) {
    companion object {
        const val CURRENT_VERSION = 2
    }
}

/** 병합 결과. */
data class TodoSyncMergeResult(val items: List<TodoItem>, val pending: Set<String>, val heldRejectedIDs: Set<String>, val deferredIDs: Set<String>)

/** 투두의 모든 판정을 값으로만 내리는 순수 규칙(자정 경계 같은 건 실행 시각에 기대지 않는다). */
object TodoRules {
    /** 제목 상한(글자 = 그래핌). 넘으면 **거부**한다(몰래 자르지 않는다). */
    const val maxTitleLength = 100
    /** 제목의 코드포인트 상한(서버 char_length 1…1000). */
    const val maxTitleCodePoints = 1000
    const val counterVisibleFrom = 90
    const val oldItemDays = 7
    const val purgeDays = 90
    const val undoSeconds = 5.0

    /** 유니코드 정준 결합 → 제어/서식 제거(공백성은 공백으로) → 공백 1칸 접기 → 앞뒤 제거. ZWJ 는 둔다(이모지가 쪼개진다). */
    fun normalizedTitle(raw: String): String {
        val composed = TextNormalization.nfc(raw).codePointArray()
        val cleaned = ArrayList<Int>(composed.size)
        for (scalar in composed) {
            if (scalar == 0x200D) {
                cleaned += scalar
                continue
            }
            val category = TextScalars.generalCategory(scalar)
            if (category == "Cc" || category == "Cf") {
                if (TextScalars.isWhiteSpaceProperty(scalar)) cleaned += 0x20
                continue
            }
            cleaned += scalar
        }
        // Swift `split(whereSeparator: { $0.isWhitespace })` — 글자(그래핌) 단위, 그 글자의 **첫 스칼라**가 White_Space 면 가르개.
        val parts = ArrayList<String>()
        val current = StringBuilder()
        for (cluster in Graphemes.clusters(stringFromCodePoints(cleaned.toIntArray()))) {
            val first = cluster.codePointArray().firstOrNull() ?: continue
            if (TextScalars.isWhiteSpaceProperty(first)) {
                if (current.isNotEmpty()) {
                    parts += current.toString()
                    current.clear()
                }
            } else {
                current.append(cluster)
            }
        }
        if (current.isNotEmpty()) parts += current.toString()
        return parts.joinToString(" ")
    }

    /** 두 상한(글자 100 · 코드포인트 1000) 안인가 — 입력칸 · 초안 · 추가 · 수정 네 문이 이 하나를 쓴다. */
    fun titleFitsLimits(title: String): Boolean = Graphemes.count(title) <= maxTitleLength && title.codePointCountCompat() <= maxTitleCodePoints

    /** KST yyyyMMdd — MilestoneTracker 의 하루 정의를 그대로 쓴다(하루의 정의가 둘이 되지 않게). */
    fun dayKey(date: Double): String = MilestoneTracker.dayKey(date)

    /** dayKey → 그 날 KST 0시. ASCII 숫자 8자가 아니면 null(lenient 달력). */
    private fun dayStart(key: String): Double? {
        if (key.length != 8 || key.any { it !in '0'..'9' }) return null
        // Swift `key.count == 8` 은 그래핌 수 — ASCII 숫자만 통과하니 UTF-16 길이와 같다.
        return KstCalendar.date(key.substring(0, 4).toInt(), key.substring(4, 6).toInt(), key.substring(6, 8).toInt())
    }

    /** 만든 날부터 오늘까지 넘어온 KST 달력 날 수(깨진 키 · 미래면 0). */
    fun carriedDays(originDayKey: String, todayKey: String): Int {
        val origin = dayStart(originDayKey) ?: return 0
        val today = dayStart(todayKey) ?: return 0
        return maxOf(0, KstCalendar.daysBetween(origin, today))
    }

    /** 오늘 만든 항목엔 배지가 없다. 1 = "어제", N = "N일 전". */
    fun carryBadge(days: Int): String? = when {
        days < 1 -> null
        days == 1 -> "어제"
        else -> "${days}일 전"
    }

    /** 오늘 목록에 뜨는가 — 미완료는 계속, 완료는 그날 안에만, 삭제는 안 보인다. */
    fun isVisible(item: TodoItem, todayKey: String): Boolean {
        if (item.deletedAt != null) return false
        val completedAt = item.completedAt ?: return true
        return dayKey(completedAt) == todayKey
    }

    /** '오래된 항목'으로 내릴 대상(미완료 + 이월 7일 이상). */
    fun isOld(item: TodoItem, todayKey: String): Boolean {
        if (item.completedAt != null) return false
        return carriedDays(item.originDayKey, todayKey) >= oldItemDays
    }

    fun visible(items: List<TodoItem>, todayKey: String): List<TodoItem> = visible(items, todayKey, null)

    /** 되돌리기 창 동안 방금 지운 항목 하나를 그 자리에 남기는 변형. */
    fun visible(items: List<TodoItem>, todayKey: String, keepingDeleted: String?): List<TodoItem> =
        items.filter { isVisible(it, todayKey) || (it.deletedAt != null && it.id == keepingDeleted) }.sortedWith(ORDER)

    /** 미완료 먼저 · 완료끼리는 최근 완료 먼저 · 만든 시각 최신 먼저 · id(대문자 uuid 글자). */
    private val ORDER = Comparator<TodoItem> { a, b ->
        when {
            a.isDone != b.isDone -> if (!a.isDone) -1 else 1
            else -> {
                if (a.isDone) {
                    val ac = a.completedAt ?: a.updatedAt
                    val bc = b.completedAt ?: b.updatedAt
                    if (ac != bc) return@Comparator if (ac > bc) -1 else 1
                }
                if (a.createdAt != b.createdAt) return@Comparator if (a.createdAt > b.createdAt) -1 else 1
                a.id.uppercase().compareTo(b.id.uppercase())
            }
        }
    }

    /** purgeDays(KST 달력)보다 오래된 **완료/삭제** 항목을 뺀다. 미완료는 남는다. */
    fun pruned(items: List<TodoItem>, now: Double): List<TodoItem> {
        val cutoff = KstCalendar.addDays(now, -purgeDays)
        return items.filter { item ->
            val deleted = item.deletedAt
            val completed = item.completedAt
            !(deleted != null && deleted < cutoff) && !(completed != null && completed < cutoff)
        }
    }

    private const val MILLISECONDS_LIMIT = 8_640_000_000_000_000.0

    /** Date → epoch ms — **가장 가까운 정수로 반올림**(0.5 → 0 에서 먼 쪽), NaN → 0, ±8.64e15 로 누른다. */
    fun milliseconds(date: Double): Long {
        val raw = roundedHalfAwayFromZero(date * 1000)
        if (raw.isNaN()) return 0
        return minOf(maxOf(raw, -MILLISECONDS_LIMIT), MILLISECONDS_LIMIT).toLong()
    }

    /** epoch ms → Date(Swift `Date(timeIntervalSince1970: ms / 1000)` — 기준일 왕복을 거친 값, [SwiftDate]). */
    fun date(milliseconds: Long): Double = SwiftDate.since1970(milliseconds.toDouble() / 1000)

    fun normalizedTime(date: Double): Double = date(milliseconds(date))

    /**
     * 서버 응답을 로컬 사본에 합친다 — 서버 `todo_sync` 의 LWW 와 같은 규칙(⓪~⑤, 골든 todo/rules spec). 멱등이다.
     * `protected`(편집 중 · 되돌리기 창)는 ③④ 를 미루고 그 id 를 pending 에 다시 넣어 `deferredIDs` 로 알린다.
     */
    fun mergedSync(
        local: List<TodoItem>,
        pending: Set<String>,
        sent: Map<String, Long>,
        server: List<TodoItem>,
        rejected: Set<String>,
        full: Boolean,
        held: Set<String> = emptySet(),
        protected: Set<String> = emptySet(),
    ): TodoSyncMergeResult {
        val localByID = LinkedHashMap<String, TodoItem>()
        for (item in local) if (item.id !in localByID) localByID[item.id] = item
        val serverByID = LinkedHashMap<String, TodoItem>()
        val serverOrder = ArrayList<String>()
        for (item in server) {
            if (item.id !in serverByID) serverOrder += item.id
            serverByID[item.id] = item   // 같은 id 가 둘이면 뒤의 것(Swift 대입과 같다)
        }
        // ⓪
        val nextPending = pending.filter { it in localByID }.toMutableSet()
        val nextHeld = held.filter { it in localByID && it !in nextPending }.toMutableSet()
        // ①
        for ((id, sentMs) in sent) if (localByID[id]?.updatedAtMs == sentMs) nextPending.remove(id)
        // ②
        for (id in rejected) {
            val localItem = localByID[id] ?: continue
            val unchangedSinceSent = sent[id] == null || localItem.updatedAtMs == sent[id]
            val serverRowDiffers = serverByID[id] != localItem
            if (unchangedSinceSent) {
                nextPending.remove(id)
                if (serverRowDiffers) nextHeld += id
            } else {
                nextHeld.remove(id)
                if (serverRowDiffers) nextPending += id
            }
        }
        val deferred = LinkedHashSet<String>()
        val merged = ArrayList<TodoItem>()
        val emitted = HashSet<String>()
        for (item in local) {
            if (!emitted.add(item.id)) continue
            val incoming = serverByID[item.id]
            if (incoming != null) {
                // ③
                when {
                    item.id in nextHeld -> merged += item
                    item.id in nextPending && item.updatedAtMs > incoming.updatedAtMs -> merged += item
                    item.id in protected -> {
                        merged += item
                        if (incoming != item) {
                            nextPending += item.id
                            deferred += item.id
                        }
                    }
                    else -> {
                        merged += incoming
                        nextPending.remove(item.id)
                    }
                }
            } else if (full && item.id !in nextPending && item.id !in nextHeld) {
                // ④
                if (item.id in protected) {
                    merged += item
                    nextPending += item.id
                    deferred += item.id
                }
            } else {
                merged += item
            }
        }
        // ⑤
        for (id in serverOrder) if (id !in emitted) serverByID[id]?.let { merged += it }
        return TodoSyncMergeResult(merged, nextPending, nextHeld, deferred)
    }
}
