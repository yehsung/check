// 원본: Sources/CheckMobileKit/Messages/MessagesRules.swift @ 1b8260d (+ Components/MobileComponentModels.swift:41-49 PresenceStatus)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.MessageBody
import com.yehsung.aingcheck.core.rules.text.MessageHistoryReadSnapshot
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.rules.text.MessageOptimisticRead
import com.yehsung.aingcheck.core.rules.text.MessageThread
import com.yehsung.aingcheck.core.rules.text.MessageThreadBuilder
import com.yehsung.aingcheck.core.rules.text.MessageUnreadRules
import com.yehsung.aingcheck.core.rules.text.MessageUnreadSummarySnapshot
import com.yehsung.aingcheck.core.rules.text.StatusMessage
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import com.yehsung.aingcheck.core.wire.models.MessageUnreadSummary
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.sortedForPokeDisplay
import kotlin.math.abs
import kotlinx.datetime.TimeZone

/*
 * 메시지 탭의 **순수 규칙**(SPEC-ios §3.3 · SPEC-ios-build D4). 스토어와 화면이 같은 표를 읽고, 시험이 헤드리스로 잰다.
 *
 * 코어(W1-c `MessageRules`)에 이미 있는 것 — 묶기·정렬·날짜 구분선·안 읽음 상대·읽음 경계·안내 문구 — 은 **그대로 부른다.**
 * 여기 있는 것은 폰 화면만의 규칙이다: 탭 배지 숫자 · 보내는 중 말풍선 정리 · 입력 카운터 · 사람 찾기 · 대화 줄 모양 · 바닥 따라가기.
 * 달력은 언제나 KST 다([MessagesTime.kst] — Swift `MobileRelativeTime.kst`).
 */
// INV-MessagesRules-6c27a9b4 이식: 이 파일(과 이 모듈)에는 로그(print · Logger)가 없다 — 메시지 본문은 사람이 쓴 문장이다.

/** 요약 한 번의 사실(Swift `MessageUnreadSummarySnapshot` — 개수까지 든 전선 요약). W1-c 규칙에는 [forRules] 로 넘긴다. */
data class MessagesSummarySnapshot(val serial: Int, val summary: MessageUnreadSummary) {
    val forRules: MessageUnreadSummarySnapshot get() = MessageUnreadSummarySnapshot(serial, summary.unreadPeerIDs)
}

// ---------------------------------------------------------------- 탭 배지 숫자

object MessagesBadgeRules {
    /**
     * 안 읽은 **메시지 수**(탭 배지). 판정 재료와 선택 규칙은 `MessageUnreadRules.unreadPeerIDs` 와 **같다** —
     * 서버 스냅샷(이력의 읽음 칸 · 요약) 중 더 나중에 띄운 쪽, 그 스냅샷이 모르는 낙관 읽음은 뺀다.
     * 그래서 "점이 하나라도 있다 ⇔ 숫자 > 0" 이 늘 성립한다.
     */
    fun unreadCount(
        history: List<MessageEntry>,
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessagesSummarySnapshot?,
        optimistic: Map<String, MessageOptimisticRead>,
        legacyStamps: Map<String, Double>,
    ): Int = unreadCountsByPeerAll(history, historySnapshot, summary, optimistic, legacyStamps, dropZero = false).values.sum()

    /**
     * 상대별 안 읽은 메시지 수(목록 줄 오른쪽 개수 배지). [unreadCount] 와 **같은 갈래 · 같은 재료**다: 값의 합 = [unreadCount],
     * 키 ⊆ `MessageUnreadRules.unreadPeerIDs`. 0 인 상대는 넣지 않는다.
     */
    fun unreadCountsByPeer(
        history: List<MessageEntry>,
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessagesSummarySnapshot?,
        optimistic: Map<String, MessageOptimisticRead>,
        legacyStamps: Map<String, Double>,
    ): Map<String, Int> = unreadCountsByPeerAll(history, historySnapshot, summary, optimistic, legacyStamps, dropZero = true)

    private fun unreadCountsByPeerAll(
        history: List<MessageEntry>,
        historySnapshot: MessageHistoryReadSnapshot?,
        summary: MessagesSummarySnapshot?,
        optimistic: Map<String, MessageOptimisticRead>,
        legacyStamps: Map<String, Double>,
        dropZero: Boolean,
    ): Map<String, Int> {
        val counts = LinkedHashMap<String, Int>()
        val useHistory = when {
            historySnapshot == null && summary == null -> {
                for (peer in MessageUnreadRules.legacyUnreadPeerIDs(history, legacyStamps)) {
                    val stamp = legacyStamps[peer]
                    val count = history.count { entry ->
                        entry.peerUserID == peer && !entry.isMine && (stamp == null || entry.createdAt > stamp)
                    }
                    if (count > 0) counts[peer] = count
                }
                return counts
            }
            summary == null -> true
            historySnapshot == null -> false
            else -> historySnapshot.serial > summary.serial
        }
        if (useHistory && historySnapshot != null) {
            val order = MessageUnreadRules.effectiveOrder(history, historySnapshot.serverOrder)
            for (entry in history) {
                if (entry.isMine || entry.isUnread != true) continue
                val record = optimistic[entry.peerUserID]
                if (record != null && !record.isKnown(historySnapshot.serial) && MessageUnreadRules.isCovered(entry, record, order)) continue
                counts[entry.peerUserID] = (counts[entry.peerUserID] ?: 0) + 1
            }
            return counts
        }
        summary ?: return counts
        for (peer in summary.summary.peers) {
            if (dropZero && peer.count <= 0) continue
            val record = optimistic[peer.peerUserID]
            if (record != null && !record.isKnown(summary.serial)) continue
            counts[peer.peerUserID] = (counts[peer.peerUserID] ?: 0) + peer.count.toInt()
        }
        return counts
    }
}

// ---------------------------------------------------------------- 보내는 중 말풍선

/**
 * 보내기 버튼을 누른 순간부터 서버 이력이 그 말을 들고 올 때까지 대화 끝에 서는 **자리 말풍선**.
 * 이력(`history`)과 따로 살고 화면만 끝에 붙여 그린다 — 읽음 경계·안 읽음 계산·정렬은 이 값을 모른다.
 */
data class MessagesPendingOutgoing(
    val id: String,
    val peerUserID: String,
    /** 정규화한 본문(`MessageBody.validate` 의 ok 값 — 서버로 보낸 그 글자). */
    val body: String,
    val createdAt: SwiftDate,
    val state: State,
) {
    sealed interface State {
        /** 서버 왕복 중. */
        data object sending : State

        /** 서버가 받았다(ok). 번호는 응답을 받은 순간의 일련번호 — 그보다 **나중에 띄운** 이력이 반영되면 사라진다. */
        data class sent(val settledSerial: Int) : State
    }
}

object MessagesPendingRules {
    /** 본문이 같은 새 서버 행을 "그 자리 말풍선의 진짜 행"으로 볼 시각 창(초). */
    const val bodyMatchWindowSeconds: Double = 600.0

    /**
     * 이력 응답(`appliedSerial` 로 띄운 것)을 반영한 뒤 남길 자리 말풍선.
     *  1. 응답을 받은 뒤(`sent`)에 띄운 이력이 반영됐으면 → 서버가 그 말을 안다. 지운다.
     *  2. 이번 응답에 **처음 나타난** 내 말(같은 상대 · 같은 본문 · 시각 창 안)이 있으면 → 그 행이 진짜다. 하나씩 짝지어 지운다.
     *  3. 나머지는 남긴다.
     */
    fun reconcile(
        pending: List<MessagesPendingOutgoing>,
        previousHistoryIDs: Set<String>,
        applied: List<MessageEntry>,
        appliedSerial: Int,
    ): List<MessagesPendingOutgoing> {
        if (pending.isEmpty()) return emptyList()
        val claimed = HashSet<String>()
        val kept = ArrayList<MessagesPendingOutgoing>()
        for (item in pending) {
            val state = item.state
            if (state is MessagesPendingOutgoing.State.sent && appliedSerial > state.settledSerial) continue
            val match = applied.firstOrNull { entry ->
                entry.isMine && entry.peerUserID == item.peerUserID && entry.body == item.body &&
                    entry.id !in previousHistoryIDs && entry.id !in claimed &&
                    abs(entry.createdDate.timeIntervalSince(item.createdAt)) <= bodyMatchWindowSeconds
            }
            if (match != null) {
                claimed += match.id
                continue
            }
            kept += item
        }
        return kept
    }
}

// ---------------------------------------------------------------- 보내기 결과 문구

object MessagesSendRules {
    /** 네트워크·서버 장애·함수 없음. 맥 `WorkTimerStore.sendMessage` 의 catch 문장과 **같은 글자**다. */
    const val connectionNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"

    /** 서버 status → 입력칸 위 한 줄. 성공은 null. `flood` 는 조용한 일반 안내로 접는다(카운트다운 금지). */
    fun notice(outcome: MessageSendOutcome, maxLength: Long?): String? = when (outcome) {
        MessageSendOutcome.Ok -> null
        MessageSendOutcome.NotWorking -> MessageNoticeText.notWorking
        MessageSendOutcome.TargetNotWorking -> MessageNoticeText.targetNotWorking
        MessageSendOutcome.TargetFocused -> MessageNoticeText.targetFocused
        MessageSendOutcome.TooLong -> MessageNoticeText.tooLong(maxLength?.toInt())
        MessageSendOutcome.NotText -> MessageNoticeText.notText
        MessageSendOutcome.Blackout -> MessageNoticeText.blackout
        MessageSendOutcome.Flood, MessageSendOutcome.Invalid -> MessageNoticeText.invalid
    }
}

// ---------------------------------------------------------------- 입력칸

object MessagesComposerRules {
    /** 카운터를 보이기 시작하는 길이(코드포인트). */
    const val counterThreshold = 180

    /** "185/200" — 180 미만이면 null. 눈금은 `MessageBody.length`(서버 char_length 와 같은 코드포인트)다. */
    fun counterText(draft: String): String? {
        val length = MessageBody.length(draft)
        if (length < counterThreshold) return null
        return "$length/${MessageBody.maxLength}"
    }

    fun isOverflowing(draft: String): Boolean = MessageBody.length(draft) > MessageBody.maxLength

    const val placeholder = "메시지 입력"

    /** 손가락으로 누르는 자리의 최소 변(pt · HIG 44 — Android 48dp 와 화면 갈래가 맞춘다). */
    const val minimumTouchTarget: Double = 44.0
    const val sendButtonMaxDiameter: Double = 52.0
    const val sendGlyphRatio: Double = 0.4
    const val sendVisibleRatio: Double = 0.73

    data class SendButtonMetrics(val diameter: Double, val glyphSize: Double) {
        val visibleDiameter: Double get() = roundedHalfAwayFromZero(diameter * sendVisibleRatio)
        val visibleGlyphSize: Double
            get() = minOf(roundedHalfAwayFromZero(glyphSize * 0.85), roundedHalfAwayFromZero(visibleDiameter * 0.5))
    }

    fun sendButtonMetrics(scaledDiameter: Double): SendButtonMetrics {
        val scaled = if (scaledDiameter.isFinite()) scaledDiameter else minimumTouchTarget
        val diameter = minOf(maxOf(scaled, minimumTouchTarget), sendButtonMaxDiameter)
        return SendButtonMetrics(diameter, roundedHalfAwayFromZero(diameter * sendGlyphRatio))
    }

    /** [보내기]를 눌렀을 때 화면이 할 일. **한글 조합 중에는 보내지 않는다**(조합을 먼저 확정하고 다시 판정해 보낸다). */
    enum class SendAction { none, commitThenSend, send }

    fun sendAction(isComposing: Boolean, canSendCommittedDraft: Boolean): SendAction = when {
        isComposing -> SendAction.commitThenSend
        canSendCommittedDraft -> SendAction.send
        else -> SendAction.none
    }
}

// ---------------------------------------------------------------- 사람 찾기

object MessagesDirectoryRules {
    private val choseong: List<Int> = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".map { it.code }

    /**
     * 이름 검색. 빈 검색어면 전부(**안 읽음 먼저 → 근무 중 먼저 → 이름순** — 와이어 `sortedForPokeDisplay`).
     * - 보통 검색: 대소문자·발음 구별 없이 이름에 들어 있으면.
     * - 초성 검색: 검색어가 한글 자음(ㄱ~ㅎ)만이면 이름의 초성열에 들어 있으면("ㅎㄱ" → "한결").
     *
     * `unreadPeerIDs` 는 **메시지 안 읽음 ∪ 안 본 찌르기**다(합치는 자리는 스토어 `sortUnreadPeerIDs`). 명부 엔트리는 자기 `isWorking` 을
     * 서버에서 들고 오므로 근무 축은 언제나 '안다'(`workKnown = true`).
     */
    // INV-MessagesRules-51241256 이식: 기본값을 달지 않는다 — unreadPeerIDs · collation 둘 다 부르는 쪽이 언제나 넘긴다.
    fun filter(
        entries: List<PokeDirectoryEntry>,
        query: String,
        unreadPeerIDs: Set<String>,
        collation: Collation,
    ): List<PokeDirectoryEntry> {
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(query)
        val sorted = entries.sortedForPokeDisplay(unreadPeerIDs = unreadPeerIDs, workKnown = true, collation = collation)
        if (trimmed.isEmpty()) return sorted
        val compact = SwiftStrings.scalars(trimmed).filter { !TextScalars.isWhiteSpaceProperty(it) }
        if (compact.isNotEmpty() && compact.all { it in choseong }) {
            val needle = codePointsToString(compact)
            return sorted.filter { initials(it.name).contains(needle) }
        }
        return sorted.filter { SearchFolding.contains(it.name, trimmed) }
    }

    /** 이름의 초성열(한글 음절만 초성으로 바꾸고, 나머지 글자는 그대로 · 공백(White_Space)은 뺀다). */
    fun initials(name: String): String {
        val out = ArrayList<Int>()
        for (scalar in SwiftStrings.scalars(name)) {
            if (TextScalars.isWhiteSpaceProperty(scalar)) continue
            out += if (scalar in 0xAC00..0xD7A3) choseong[(scalar - 0xAC00) / 588] else scalar
        }
        return codePointsToString(out)
    }
}

internal fun codePointsToString(cps: List<Int>): String {
    val sb = StringBuilder()
    for (cp in cps) {
        if (cp >= 0x10000) {
            val v = cp - 0x10000
            sb.append((0xD800 + (v shr 10)).toChar())
            sb.append((0xDC00 + (v and 0x3FF)).toChar())
        } else {
            sb.append(cp.toChar())
        }
    }
    return sb.toString()
}

/** 플랫폼 정준 분해(NFD — JVM·ART `java.text.Normalizer`). 범주 판정은 번들 표가 한다. */
internal expect fun canonicalDecomposition(text: String): String

/**
 * Foundation `range(of:options: [.caseInsensitive, .diacriticInsensitive]) != nil` 자리. 발음 구별 부호(범주 Mn — 번들 표)를 걷고
 * 대소문자를 접은 뒤 포함 여부를 본다. **한글 음절은 분해하지 않는다**(분해하면 "하" 가 "한" 안에서 찾아진다 — Foundation 은 음절 단위다).
 * 골든 `messages/store-rules` 의 directory 사례가 Swift 답과 대조한다.
 */
object SearchFolding {
    fun fold(text: String): String {
        val out = ArrayList<Int>(text.length)
        for (cp in SwiftStrings.scalars(text)) {
            val pieces = if (cp in 0xAC00..0xD7A3) intArrayOf(cp) else SwiftStrings.scalars(canonicalDecomposition(codePointsToString(listOf(cp))))
            for (p in pieces) {
                if (TextScalars.generalCategory(p) == "Mn") continue
                out += p
            }
        }
        return codePointsToString(out).lowercase()
    }

    fun contains(haystack: String, needle: String): Boolean = fold(haystack).contains(fold(needle))
}

// ---------------------------------------------------------------- 근무 상태(Components/MobileComponentModels.swift:41-49)

/** 사람 점이 말하는 근무 상태: working 초록 · pending 앰버(연결 끊김 — 우리 팀만 안다) · off 점 없음. */
enum class PresenceStatus(val rawValue: String) { working("working"), pending("pending"), off("off") }

// ---------------------------------------------------------------- 콕/메시지 4단 정렬 · 찌르기가 낀 대화 목록 (1.0.13)
//
// 사용자 결정(2026-10-23): 1. 근무중+안읽음 2. 근무안함+안읽음 3. 근무중+다읽음 4. 근무안함+다읽음 · "안 본 찌르기도 '안 읽음'으로 친다".
// 맥(0.3.65)과 같은 규칙이다. 폰에는 목록이 둘이다: 대화 목록(같은 무리 안은 최근순) · 사람 찾기 명부(같은 무리 안은 이름순).

// INV-MessagesRules-1caea24e 이식: 줄을 세우는 규칙은 여기 한 벌뿐이다(MessagesThreadListRules.rows) — 화면은 MessagesStore.threadItems(now) 를 그대로 그린다.

/**
 * 대화 목록 한 줄(1.0.13). 코어 대화(`MessageThread`) + 그 사람과 오간 찌르기 + **다 정해진 표시값**.
 */
// INV-MessagesRules-cc38d25c 이식: 찌르기만 있는 사람도 한 줄이 선다(그때 thread.messages 는 빈 배열) — 시험 threadRowsStandForPokeOnlyPeers.
data class MessagesThreadItem(
    val thread: MessageThread<MessageEntry>,
    val pokes: List<MessagePokeLogEntry>,
    /** 목록 정렬·오른쪽 위 시각의 기준 = **찌르기를 포함한 마지막 활동**. */
    val lastActivityAt: SwiftDate,
    val previewText: String,
    val lastIsMine: Boolean,
    /** 미리보기가 **찌르기 문구**인가(그 문구는 주어를 이미 말해 "나: "를 덧붙이지 않는다). */
    val previewIsPoke: Boolean,
    val timeText: String,
    /** 굵게 · 위로 올리는 기준 = 안 읽은 메시지 ∪ 안 본 찌르기. */
    val isUnread: Boolean,
    /** 개수 배지. **메시지** 안 읽음에만 선다(찌르기뿐이면 null). */
    val countBadge: String?,
    /** 정렬 무리(근무를 알면 0…3, 모르면 0·2). */
    val group: Int,
) {
    val previewNeedsMinePrefix: Boolean get() = lastIsMine && !previewIsPoke
    val id: String get() = thread.peerUserID
    val peerUserID: String get() = thread.peerUserID
    val peerName: String get() = thread.peerName
    val peerAvatarURL: String? get() = thread.peerAvatarURL
}

object MessagesThreadListRules {
    const val unseenPokeAccessibilityLabel = "안 본 찌르기"

    /** Swift `Date.distantPast`(0001-01-01 — 활동이 없는 줄의 정렬 자리). */
    val distantPast: SwiftDate = SwiftDate.fromReferenceDate(-63_114_076_800.0)

    /**
     * 대화 목록 줄 전체 — 재료 모으기(스레드 ∪ 찌르기) → 표시값 → 4단 정렬. **화면이 지나는 유일한 자리**다.
     * - `messageUnreadPeerIDs`: 안 읽은 **메시지**가 있는 상대(숫자 배지의 근거).
     * - `pokeUnreadPeerIDs`: 안 **본** 찌르기가 있는 상대(낙관 읽음을 뺀 값).
     * - `chronology`: 서버 시각 순위(같은 초의 메시지·찌르기 선후). 대화 화면과 **같은 표**.
     */
    fun rows(
        threads: List<MessageThread<MessageEntry>>,
        pokes: List<MessagePokeLogEntry>,
        chronology: Map<String, Int>,
        messageUnreadPeerIDs: Set<String>,
        pokeUnreadPeerIDs: Set<String>,
        unreadCounts: Map<String, Int>,
        workingPeerIDs: Set<String>,
        workKnown: Boolean,
        now: SwiftDate,
        zone: TimeZone = MessagesTime.kst,
    ): List<MessagesThreadItem> {
        val unread = MessagesSortRules.combinedUnreadPeerIDs(messageUnreadPeerIDs, pokeUnreadPeerIDs)
        val decorated = items(threads, pokes, chronology, zone).map { item ->
            val peer = item.peerUserID
            val isUnread = peer in unread
            item.copy(
                timeText = MessagesListRules.timeText(item.lastActivityAt, now, zone),
                isUnread = isUnread,
                // INV-MessagesRules-616eea1f 이식: 숫자는 메시지 안 읽음에만(찌르기뿐인 행은 null — 배지는 메시지만 센다).
                countBadge = if (peer in messageUnreadPeerIDs) MessagesListRules.countBadge(true, unreadCounts[peer]) else null,
                group = MessagesSortRules.rank(isUnread, peer in workingPeerIDs, workKnown),
            )
        }
        return MessagesSortRules.sortedThreads(decorated)
    }

    /** 코어 대화 + 찌르기 기록 → 목록 줄 재료(표시값·정렬 전). 들어온 찌르기 배열의 순서를 믿지 않는다(`MessagePokeLogRules.sorted`). */
    internal fun items(
        threads: List<MessageThread<MessageEntry>>,
        pokes: List<MessagePokeLogEntry>,
        chronology: Map<String, Int>,
        zone: TimeZone,
    ): List<MessagesThreadItem> {
        fun plain(thread: MessageThread<MessageEntry>): MessagesThreadItem {
            val last = thread.lastMessage
            return draft(thread, emptyList(), last?.createdDate ?: distantPast, last?.let { MessagesListRules.preview(it.body) } ?: "",
                last?.isMine ?: false)
        }
        if (pokes.isEmpty()) return threads.map(::plain)
        val ordered = MessagePokeLogRules.sorted(pokes, chronology)
        val byPeer = LinkedHashMap<String, MutableList<MessagePokeLogEntry>>()
        for (poke in ordered) byPeer.getOrPut(poke.peerUserID) { mutableListOf() } += poke
        val items = threads.mapTo(ArrayList()) { thread -> item(thread, byPeer[thread.peerUserID] ?: emptyList(), chronology, zone) }
        val known = threads.map { it.peerUserID }.toSet()
        val pokeOnlyOrder = ArrayList<String>()
        for (poke in ordered) if (poke.peerUserID !in known && poke.peerUserID !in pokeOnlyOrder) pokeOnlyOrder += poke.peerUserID
        for (peer in pokeOnlyOrder) {
            val own = byPeer[peer] ?: emptyList()
            // 이름·아바타는 **가장 최근 행의 것**이다(코어 `MessageThreadBuilder.threads` 와 같은 규약).
            val latest = own.lastOrNull() ?: continue
            val thread = MessageThread<MessageEntry>(peer, latest.peerName, latest.peerAvatarURL?.absoluteString, emptyList())
            items += item(thread, own, chronology, zone)
        }
        return items
    }

    private fun item(
        thread: MessageThread<MessageEntry>,
        pokes: List<MessagePokeLogEntry>,
        chronology: Map<String, Int>,
        zone: TimeZone,
    ): MessagesThreadItem {
        val lastMessage = thread.lastMessage
        val lastPoke = pokes.lastOrNull()
        val anchor = lastMessage?.createdDate ?: lastPoke?.createdAt
            ?: return draft(thread, pokes, distantPast, "", false)
        // INV-MessagesRules-d44e1c07 이식: "어느 쪽이 더 최근인가"는 코어 병합 규칙(두 줄짜리 타임라인의 마지막 줄)에 묻는다 — 같은 초 선후를 여기서 다시 적지 않는다.
        val lines = MessageConversationTimeline.lines(
            messages = listOfNotNull(lastMessage),
            pokes = listOfNotNull(lastPoke),
            chronology = chronology,
            now = anchor.timeIntervalSince1970,
            zone = zone,
        )
        return when (val last = lines.lastOrNull()) {
            is MessageConversationLine.poke -> draft(
                thread, pokes, last.entry.createdAt, MessagesSortRules.pokePreview(last.entry, zone), last.entry.isMine, previewIsPoke = true,
            )
            is MessageConversationLine.bubble -> draft(
                thread, pokes, last.entry.createdDate, MessagesListRules.preview(last.entry.body), last.entry.isMine, previewIsPoke = false,
            )
            else -> draft(thread, pokes, anchor, "", false)
        }
    }

    private fun draft(
        thread: MessageThread<MessageEntry>,
        pokes: List<MessagePokeLogEntry>,
        lastActivityAt: SwiftDate,
        previewText: String,
        lastIsMine: Boolean,
        previewIsPoke: Boolean = false,
    ): MessagesThreadItem = MessagesThreadItem(
        thread = thread, pokes = pokes, lastActivityAt = lastActivityAt, previewText = previewText,
        lastIsMine = lastIsMine, previewIsPoke = previewIsPoke, timeText = "", isUnread = false, countBadge = null, group = 0,
    )

    /** 목록 줄 보이스오버. 안 읽음이 **찌르기뿐**이면 "안 읽은 메시지"라고 말하지 않는다. */
    fun accessibilityText(row: MessagesThreadItem, presenceLine: String?): String {
        val parts = arrayListOf(row.peerName)
        if (presenceLine != null) parts += presenceLine
        val badge = row.countBadge
        if (badge != null) parts += "안 읽은 메시지 ${badge}개" else if (row.isUnread) parts += unseenPokeAccessibilityLabel
        parts += (if (row.previewNeedsMinePrefix) "나: " else "") + row.previewText
        parts += row.timeText
        return parts.joinToString(", ")
    }
}

object MessagesSortRules {
    /** 정렬이 쓰는 안 읽음 = **안 읽은 메시지 ∪ 안 본 찌르기**. */
    // INV-MessagesRules-10485b92 이식: 이 합친 집합을 "안 읽은 메시지 N"·탭 배지·줄 개수 배지에 먹이지 않는다(그 수는 메시지 전용) — 시험 countBadgeIsMessageOnly.
    fun combinedUnreadPeerIDs(messages: Set<String>, pokes: Set<String>): Set<String> = if (pokes.isEmpty()) messages else messages + pokes

    /** 근무 중으로 치는 상태. **pending(앰버 점 · 연결 끊김)도 근무중이다**. */
    fun isWorking(presence: MessagesPeerPresence?): Boolean = when (presence?.status) {
        PresenceStatus.working, PresenceStatus.pending -> true
        PresenceStatus.off, null -> false
    }

    fun workingPeerIDs(board: MessagesPresenceBoard): Set<String> {
        if (!board.isKnown) return emptySet()
        return board.peers.filter { isWorking(it.value) }.keys.toSet()
    }

    /** 무리 번호(작을수록 위). 근무 여부를 **모르는 동안**에는 근무 축을 쓰지 않는다(안 읽음만으로 두 무리 — 0 · 2). */
    fun rank(isUnread: Boolean, isWorking: Boolean, workKnown: Boolean): Int {
        if (!workKnown) return if (isUnread) 0 else 2
        if (isUnread) return if (isWorking) 0 else 1
        return if (isWorking) 2 else 3
    }

    /** 대화 목록 4단 정렬: 무리 → 최근순(찌르기 포함 마지막 활동) → id(결정성). */
    fun sortedThreads(items: List<MessagesThreadItem>): List<MessagesThreadItem> = items.sortedWith { lhs, rhs ->
        if (lhs.group != rhs.group) return@sortedWith lhs.group.compareTo(rhs.group)
        if (lhs.lastActivityAt != rhs.lastActivityAt) return@sortedWith rhs.lastActivityAt.compareTo(lhs.lastActivityAt)
        SwiftStrings.compare(lhs.peerUserID, rhs.peerUserID)
    }

    /**
     * 목록 미리보기용 찌르기 한 줄 — 대화 줄과 **같은 문구**에서 시각 꼬리만 뗀다(`MessagePokeLogText.line` 에서 `clockText` 꼬리를 뗀다 —
     * "콕 찔렀어요"를 여기 다시 적지 않는다).
     */
    fun pokePreview(entry: MessagePokeLogEntry, zone: TimeZone = MessagesTime.kst): String {
        val full = MessagePokeLogText.line(entry, zone)
        val tail = " · " + MessageThreadBuilder.clockText(entry.createdAt.timeIntervalSince1970, zone)
        return if (full.endsWith(tail)) full.dropLast(tail.length) else full
    }
}

// ---------------------------------------------------------------- 목록 · 라우트

/** 메시지 탭 내비게이션 경로의 원소(Swift `MessagesDestination` — 탭이 정한다, 라우터는 모른다). */
sealed interface MessagesDestination {
    data class conversation(val peerID: String) : MessagesDestination
}

/**
 * 딥링크 중 메시지 탭 몫(Swift `AingRoute` 의 `.messages` · `.message(peerID:)` 두 갈래). 라우트 타입 `AingRoute` 는 앱 셸(W1-g
 * androidApp …/routing)에 있어 스토어 층이 볼 수 없다 — 셸·메시지 화면(W3-a)이 `AingRoute.Messages → list`, `AingRoute.Message(p) → conversation(p)`,
 * 그 밖의 라우트는 null 로 옮겨 [MessagesListRules.destinations] 를 부른다(순위 탭의 [com.yehsung.aingcheck.core.stores.rankings.RankingsBoard] 와 같은 처리).
 */
sealed interface MessagesRouteTarget {
    data object list : MessagesRouteTarget
    data class conversation(val peerID: String) : MessagesRouteTarget
}

object MessagesListRules {
    /** 딥링크 → 메시지 탭 경로(Swift `destinations(for:)`). 메시지 탭 라우트가 아니면(null) null. 목록은 빈 경로(목록 맨 위). */
    fun destinations(route: MessagesRouteTarget?): List<MessagesDestination>? = when (route) {
        null -> null
        MessagesRouteTarget.list -> emptyList()
        is MessagesRouteTarget.conversation -> listOf(MessagesDestination.conversation(route.peerID))
    }

    /**
     * 목록 한 줄 미리보기: 줄바꿈·연속 공백을 한 칸으로 접는다. 아잉이 이모티콘을 **먼저** 거친다(목록은 그림을 못 그린다).
     */
    // INV-MessagesRules-5f8f5138 이식: 순서가 거꾸로면 안 된다 — 이모티콘 판정(AingStickerText.preview)이 정규화 원문을 먼저 보고, 접기는 그 뒤다.
    fun preview(body: String): String {
        val text = AingStickerText.preview(body)
        // Swift `split(whereSeparator: { $0.isWhitespace || $0.isNewline })` — 글자(그래핌)의 첫 스칼라가 White_Space 면 가르개(줄바꿈 넷도 White_Space).
        val words = ArrayList<String>()
        val current = StringBuilder()
        for (cluster in Graphemes.clusters(text)) {
            val first = SwiftStrings.scalars(cluster).firstOrNull()
            if (first != null && TextScalars.isWhiteSpaceProperty(first)) {
                if (current.isNotEmpty()) {
                    words += current.toString()
                    current.clear()
                }
            } else {
                current.append(cluster)
            }
        }
        if (current.isNotEmpty()) words += current.toString()
        return words.joinToString(" ")
    }

    /** 목록 줄 오른쪽 위 시각: 오늘이면 "13:58"(24시간제), 아니면 "어제"·"9월 8일". */
    fun timeText(date: SwiftDate, now: SwiftDate, zone: TimeZone = MessagesTime.kst): String {
        val d = date.timeIntervalSince1970
        val n = now.timeIntervalSince1970
        if (MessagesTime.isSameDay(d, n, zone)) return MessageThreadBuilder.clockText(d, zone)
        return MessageThreadBuilder.dayLabel(d, n, zone)
    }

    /** 큰 제목 아래 한 줄("안 읽은 메시지 3"). 0 이면 null. */
    fun subtitle(unreadCount: Int): String? = if (unreadCount > 0) "안 읽은 메시지 $unreadCount" else null

    /** 목록 줄 개수 배지. 점 집합에 있으면 최소 1 · 없으면 null · 100 부터 "99+". */
    fun countBadge(isUnread: Boolean, count: Int?): String? {
        if (!isUnread) return null
        val value = maxOf(count ?: 0, 1)
        return if (value > 99) "99+" else "$value"
    }
}

// ---------------------------------------------------------------- 대화 줄

/** 대화 화면 한 줄(코어 `MessageConversationTimeline.lines` 위에 폰의 모양 결정을 얹은 것). */
sealed interface MessagesConversationItem {
    val id: String

    /** 바닥 따라가기의 "마지막 줄이 내 것인가"(자리 말풍선은 언제나 내 것). */
    val isMine: Boolean

    data class day(val key: String, val label: String) : MessagesConversationItem {
        override val id: String get() = "day-$key"
        override val isMine: Boolean get() = false
    }

    data class bubble(val line: MessagesBubbleLine) : MessagesConversationItem {
        override val id: String get() = line.entry.id
        override val isMine: Boolean get() = line.entry.isMine
    }

    /** 찌르기 기록 줄 — **말풍선이 아니다.** 답장·읽음 표시·복사·신고 대상이 아니다. */
    data class poke(val line: MessagesPokeLogLine) : MessagesConversationItem {
        override val id: String get() = line.id
        override val isMine: Boolean get() = line.entry.isMine
    }

    data class pending(val item: MessagesPendingOutgoing) : MessagesConversationItem {
        override val id: String get() = "pending-${item.id}"
        override val isMine: Boolean get() = true
    }
}

/** 대화창 찌르기 줄 하나(그릴 값만). 글자·아이콘은 전부 [MessagePokeLogText] 가 쥔다(맥과 한 벌). */
data class MessagesPokeLogLine(val entry: MessagePokeLogEntry, val text: String, val symbol: String) {
    /** 말풍선 id 와 겹치지 않게. */
    val id: String get() = "poke-${entry.id}"
}

data class MessagesBubbleLine(
    val entry: MessageEntry,
    /** "14:05"(KST 24시간제). */
    val clockText: String,
    /** 같은 쪽·같은 분의 다음 말풍선이 이어지면 마지막 것에만 찍는다. */
    val showsTime: Boolean,
    /** 말한 쪽이 바뀐 첫 말풍선(앞 줄이 다른 쪽 말풍선). */
    val startsGroup: Boolean,
    /** 내 말풍선 옆 **1**(서버가 읽음을 알고 · 내 말이고 · readByPeer == false). */
    val showsUnreadOne: Boolean,
)

data class MessagesEmptyState(val symbol: String, val title: String, val hint: String?, val showsRetry: Boolean)

data class MessagesConversationHeader(
    val title: String,
    /** 이니셜 아바타에 넘길 이름. null = 이름을 모른다 → 일반 인물 아이콘(가짜 이니셜 금지). */
    val avatarName: String?,
    val accessibilityLabel: String,
) {
    companion object {
        const val fallbackTitle = "대화"
        const val resolvingAccessibilityLabel = "대화 상대를 불러오는 중"
        const val unknownAccessibilityLabel = "이름을 불러오지 못한 대화"
        const val unknownAvatarSymbol = "person.crop.circle"
    }
}

object MessagesConversationRules {
    const val unreadOneText = "1"
    const val unreadOneAccessibilityLabel = "안 읽음"

    fun showsUnreadOne(entry: MessageEntry, receiptsAvailable: Boolean): Boolean =
        receiptsAvailable && entry.isMine && entry.readByPeer == false

    /** 찌르기 줄 한 줄(글자·아이콘은 코어). 달력을 **반드시 넘긴다**(KST — 기기 시간대가 다른 사람만 말풍선과 갈리지 않게). */
    fun pokeLine(entry: MessagePokeLogEntry, zone: TimeZone = MessagesTime.kst): MessagesPokeLogLine =
        MessagesPokeLogLine(entry, MessagePokeLogText.line(entry, zone), MessagePokeLogText.symbol(entry.kind))

    /**
     * 시간순 이력(한 사람) + 그 사람과 오간 **찌르기** + 보내는 중 자리 말풍선 → 화면 줄. 끼워 넣기·날짜 줄은 코어
     * (`MessageConversationTimeline.lines`)가 한다 — 그 병합은 안정 병합이라 찌르기를 `MessagePokeLogRules.sorted` 에 먼저 통과시킨다.
     */
    fun items(
        messages: List<MessageEntry>,
        pokes: List<MessagePokeLogEntry>,
        chronology: Map<String, Int>,
        pending: List<MessagesPendingOutgoing>,
        receiptsAvailable: Boolean,
        now: SwiftDate,
        zone: TimeZone = MessagesTime.kst,
    ): List<MessagesConversationItem> {
        val timeline = MessageConversationTimeline.lines(
            messages, MessagePokeLogRules.sorted(pokes, chronology), chronology, now.timeIntervalSince1970, zone,
        )
        fun bubbleEntry(line: MessageConversationLine): MessageEntry? = (line as? MessageConversationLine.bubble)?.entry
        val items = ArrayList<MessagesConversationItem>(timeline.size + pending.size + 1)
        for ((index, item) in timeline.withIndex()) {
            when (item) {
                is MessageConversationLine.day -> items += MessagesConversationItem.day(item.key, item.label)
                is MessageConversationLine.poke -> items += MessagesConversationItem.poke(pokeLine(item.entry, zone))
                is MessageConversationLine.bubble -> {
                    val entry = item.entry
                    val clock = MessageThreadBuilder.clockText(entry.createdAt, zone)
                    // 앞뒤로 **말풍선이 아닌 줄**(날짜 · 찌르기)이 끼면 묶음이 끊긴다.
                    val previous = if (index > 0) bubbleEntry(timeline[index - 1]) else null
                    val next = if (index + 1 < timeline.size) bubbleEntry(timeline[index + 1]) else null
                    val continuesToNext = next?.let { it.isMine == entry.isMine && MessageThreadBuilder.clockText(it.createdAt, zone) == clock } ?: false
                    items += MessagesConversationItem.bubble(
                        MessagesBubbleLine(
                            entry = entry,
                            clockText = clock,
                            showsTime = !continuesToNext,
                            startsGroup = previous?.let { it.isMine != entry.isMine } ?: false,
                            showsUnreadOne = showsUnreadOne(entry, receiptsAvailable),
                        ),
                    )
                }
            }
        }
        if (pending.isNotEmpty()) {
            // 자리 말풍선은 "지금" 보냈다 — 마지막 날짜가 오늘이 아니면 오늘 구분선을 먼저 세운다.
            val n = now.timeIntervalSince1970
            val todayKey = MessageThreadBuilder.dayKey(n, zone)
            val lastDayKey = items.lastOrNull { it is MessagesConversationItem.day }?.let { (it as MessagesConversationItem.day).key }
            if (lastDayKey != todayKey) items += MessagesConversationItem.day(todayKey, MessageThreadBuilder.dayLabel(n, n, zone))
            pending.mapTo(items) { MessagesConversationItem.pending(it) }
        }
        return items
    }

    /** 빈 자리 문구(맥 `MessagePanelEmptyMessage` 와 같은 갈래·같은 문장). */
    fun emptyState(loaded: Boolean, failed: Boolean): MessagesEmptyState {
        if (failed && !loaded) {
            return MessagesEmptyState("exclamationmark.triangle", "대화를 불러오지 못했어요", MobileLoadText.checkConnection, showsRetry = true)
        }
        if (!loaded) return MessagesEmptyState("hourglass", "불러오는 중…", null, showsRetry = false)
        return MessagesEmptyState("bubble.left.and.bubble.right", "아직 주고받은 메시지가 없어요", "아래에 먼저 한마디 남겨 보세요", showsRetry = false)
    }

    /** 대화 머리. **이름을 모르면 사람처럼 꾸미지 않는다**(일반 인물 아이콘 · 받는 중인지 못 받았는지를 말한다). */
    fun header(peerName: String?, isResolving: Boolean): MessagesConversationHeader {
        val name = peerName?.let(TextScalars::trimmingWhitespacesAndNewlines)
        if (!name.isNullOrEmpty()) return MessagesConversationHeader(name, name, name)
        return MessagesConversationHeader(
            title = MessagesConversationHeader.fallbackTitle,
            avatarName = null,
            accessibilityLabel = if (isResolving) {
                MessagesConversationHeader.resolvingAccessibilityLabel
            } else {
                MessagesConversationHeader.unknownAccessibilityLabel
            },
        )
    }
}

// ---------------------------------------------------------------- 사람들의 근무 여부 · 센터

/** 한 사람의 근무 여부와 센터. [center] 는 **서버값**("seoul") — 글자로 바꾸는 곳은 `CenterLabel` 하나다. */
data class MessagesPeerPresence(val status: PresenceStatus, val center: String?)

/** "지금 근무 중 · 바로 말 걸기" 줄의 한 사람(working 또는 pending). */
data class MessagesWorkingPerson(
    val id: String,
    val name: String,
    val avatarURL: SwiftURL?,
    val status: PresenceStatus,
    val center: String?,
)

/** 메시지 탭이 그리는 사람들의 근무 판. */
data class MessagesPresenceBoard(
    /** 근무 여부를 한 번이라도 받았는가. false 면 점·"지금 근무 중" 줄을 그리지 않는다. */
    val isKnown: Boolean,
    val peers: Map<String, MessagesPeerPresence>,
    /** 근무 중(나 제외) — 우리 팀(오래 일한 순) 먼저, 그다음 이름순. */
    val working: List<MessagesWorkingPerson>,
    /** 사람별 상태메시지(이미 `StatusMessage.display` 를 지난 값, 없는 사람은 키가 없다). `peers` 와 따로 둔다. */
    val statuses: Map<String, String> = emptyMap(),
) {
    companion object {
        val unknown: MessagesPresenceBoard = MessagesPresenceBoard(isKnown = false, peers = emptyMap(), working = emptyList())
    }
}

object MessagesPresenceRules {
    /** 지금 탭이 가른 근무 중 한 사람(`NowStore.workingPeople(now)` 의 필요한 칸만). */
    data class Working(val id: String, val name: String, val avatarURL: SwiftURL?, val center: String?, val isStale: Boolean)

    /**
     * 판 만들기. **새 서버 호출이 없다** — 이미 받아 둔 값만 겹친다(뒤가 앞을 덮는다):
     *  1. `messagesDirectory` — 새 대화 시트가 받은 사람 목록(센터는 화면 글자라 서버값으로 되돌린다). null = 못 받음.
     *  2. `nowDirectory` — 지금 탭이 1분마다 받는 같은 목록(서버값 그대로). null = 못 받음.
     *  3. `teamMemberIDs` + `nowWorking` — 지금 탭이 받은 **우리 팀 상태**(가장 정확). 우리 팀원은 이 판정이 목록을 이긴다.
     * 나(`me`)는 판에 넣지 않는다. 다른 팀 근무자 이름 정렬은 [collation](Swift `localizedStandardCompare`).
     */
    fun board(
        nowWorking: List<Working>,
        teamMemberIDs: Set<String>,
        nowDirectory: List<PokeDirectoryRow>?,
        messagesDirectory: List<PokeDirectoryEntry>?,
        me: String?,
        collation: Collation,
    ): MessagesPresenceBoard {
        val isKnown = nowDirectory != null || messagesDirectory != null || teamMemberIDs.isNotEmpty()
        if (!isKnown) return MessagesPresenceBoard.unknown
        val peers = LinkedHashMap<String, MessagesPeerPresence>()
        val names = HashMap<String, Pair<String, SwiftURL?>>()
        for (entry in messagesDirectory ?: emptyList()) {
            if (entry.userID == me) continue
            peers[entry.userID] = MessagesPeerPresence(
                if (entry.isWorking) PresenceStatus.working else PresenceStatus.off,
                CenterLabel.serverValue(entry.center),
            )
            names[entry.userID] = entry.name to entry.avatarURL
        }
        for (row in nowDirectory ?: emptyList()) {
            if (row.userId == me) continue
            peers[row.userId] = MessagesPeerPresence(
                if (row.isWorking) PresenceStatus.working else PresenceStatus.off,
                row.center ?: peers[row.userId]?.center,
            )
            names[row.userId] = row.displayName to (SwiftURL.parse(row.avatarUrl) ?: names[row.userId]?.second)
        }
        for (id in teamMemberIDs) {
            if (id == me) continue
            val current = peers[id] ?: continue
            peers[id] = MessagesPeerPresence(PresenceStatus.off, current.center)
        }
        val working = ArrayList<MessagesWorkingPerson>()
        val seen = HashSet<String>()
        for (person in nowWorking) {
            if (person.id == me || !seen.add(person.id)) continue
            val status = if (person.isStale) PresenceStatus.pending else PresenceStatus.working
            val center = person.center ?: peers[person.id]?.center
            peers[person.id] = MessagesPeerPresence(status, center)
            working += MessagesWorkingPerson(person.id, person.name, person.avatarURL ?: names[person.id]?.second, status, center)
        }
        val others = peers
            .filter { (id, presence) -> presence.status == PresenceStatus.working && id !in seen }
            .map { (id, presence) ->
                MessagesWorkingPerson(id, names[id]?.first ?: "", names[id]?.second, PresenceStatus.working, presence.center)
            }
            .sortedWith { lhs, rhs ->
                val order = collation.compare(lhs.name, rhs.name)
                if (order != 0) order else SwiftStrings.compare(lhs.id, rhs.id)
            }
        return MessagesPresenceBoard(true, peers, working + others, statuses(nowDirectory, messagesDirectory, me))
    }

    /**
     * 상태메시지 겹치기 — 판과 같은 순서(뒤가 앞을 덮는다). **목록에 있는 사람은 그 목록의 값이 답이다**: 뒤 목록에 그 사람이 있고 상태가
     * 없으면 앞 목록의 옛 상태를 지운다(Swift 사전에 nil 을 넣으면 키가 지워진다). 나(`me`)는 넣지 않는다.
     */
    fun statuses(nowDirectory: List<PokeDirectoryRow>?, messagesDirectory: List<PokeDirectoryEntry>?, me: String?): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for (entry in messagesDirectory ?: emptyList()) {
            if (entry.userID == me) continue
            val value = entry.statusMessage
            if (value == null) result.remove(entry.userID) else result[entry.userID] = value
        }
        for (row in nowDirectory ?: emptyList()) {
            if (row.userId == me) continue
            val value = StatusMessage.display(row.statusMessage)
            if (value == null) result.remove(row.userId) else result[row.userId] = value
        }
        return result
    }

    /** 대화 머리 이름 아래 한 줄("근무 중 · 서울" · "연결 끊김" · "근무 안 함 · 부산"). 근무 여부를 모르면 null. */
    fun headerLine(presence: MessagesPeerPresence?): String? {
        presence ?: return null
        val state = when (presence.status) {
            PresenceStatus.working -> "근무 중"
            PresenceStatus.pending -> "연결 끊김"
            PresenceStatus.off -> "근무 안 함"
        }
        val center = CenterLabel.display(presence.center) ?: return state
        return "$state · $center"
    }
}

// ---------------------------------------------------------------- 바닥 따라가기

/**
 * 대화 스크롤의 **바닥 따라가기**(맥 v0.3.31 M4 `MessageScrollFollow` 와 같은 규칙).
 *  · 바닥 근처에서 보고 있으면 새 말이 오는 대로 따라 내려간다.
 *  · 위로 올려 옛 말을 읽는 중이면 끌어내리지 않는다 — "새 메시지 ↓" 버튼을 세운다.
 *  · 내가 보낸 말은 어디서 보냈든 따라간다.
 *  · **내용이 자라서 멀어진 것은 "위로 올렸다"가 아니다.**
 */
class MessagesScrollFollow {
    var isNearBottom: Boolean = true
        private set
    var showsNewMessageButton: Boolean = false
        private set
    private var lastContentHeight: Double? = null

    /** `distanceToBottom` = 내용 바닥 − 보이는 영역 바닥(0 이하 = 바닥). 틀이 줄어 바닥이 멀어진 것도 "올림"이 아니다. */
    fun measured(contentHeight: Double, distanceToBottom: Double, viewportChanged: Boolean = false) {
        if (!(contentHeight > 0)) return
        val grew = lastContentHeight?.let { abs(it - contentHeight) > 0.5 } ?: true
        lastContentHeight = contentHeight
        if (distanceToBottom <= nearBottomThreshold) {
            isNearBottom = true
            showsNewMessageButton = false
        } else if (!grew && !viewportChanged) {
            isNearBottom = false
        }
    }

    /** 마지막 줄이 바뀌었다. 바닥으로 따라가야 하면 true, 못 따라가면 버튼을 세운다. */
    fun lastItemChanged(isMine: Boolean): Boolean {
        if (isNearBottom || isMine) {
            isNearBottom = true
            showsNewMessageButton = false
            return true
        }
        showsNewMessageButton = true
        return false
    }

    fun jumpedToBottom() {
        isNearBottom = true
        showsNewMessageButton = false
    }

    companion object {
        const val nearBottomThreshold: Double = 60.0
        const val newMessageButtonTitle = "새 메시지 ↓"
        const val newMessageButtonMinHeight: Double = MessagesComposerRules.minimumTouchTarget
    }
}
