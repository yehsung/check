// 원본: Sources/CheckCore/MegaphoneFeed.swift:31-105 · 165-246(숫자 · 문구 · 도메인 줄 · 줄 → 도메인 · 응답 → 쪽) @ main 341eb4e3
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.messages.MegaphoneFeedRow
import kotlinx.datetime.TimeZone

// 지난 확성기 모아 보기의 규칙(맥 · 아이폰과 한 벌). 지키는 것: ① 배너가 아니다 — 줄은 [MegaphoneFeedItem] 이라는 다른 타입이라 배너 스토어에
// 들어갈 길이 막힌다 ② 문은 세 갈래(모름 · 닫힘 · 열림) ③ 자동 호출이 없다(사람이 누른 자리 · 페이지가 떠 있는 동안의 실시간 신호뿐)
// ④ 세대 가드 ⑤ 본문을 로그로 흘리지 않는다 ⑥ 꼬리 지키기는 떠 있는 동안만.

object MegaphoneFeedRules {
    /** 서버가 남기는 기간(일 — 서버 `message_store_days()`). */
    const val windowDays = 30
    /** 한 번에 받는 줄 수(`p_limit` — 계약 값). */
    const val pageSize = 30
    /** 접힌 본문의 줄 수(넘치면 그 줄에 [더 보기]). */
    const val collapsedLineLimit = 3
}

object MegaphoneFeedText {
    const val title = "지난 확성기"
    val entryLink: String get() = "$title ›"
    val windowNote: String get() = "최근 ${MegaphoneFeedRules.windowDays}일"
    val empty: String get() = "최근 ${MegaphoneFeedRules.windowDays}일 동안 울린 확성기가 없어요"
    const val loading = "불러오는 중이에요"
    const val failed = "지난 확성기를 불러오지 못했어요"
    const val unavailable = "지금은 지난 확성기를 볼 수 없어요"
    const val loadMore = "이전 확성기 더 보기"
    const val loadMoreFailed = "더 불러오지 못했어요. 다시 눌러 주세요"
    const val ownBadge = "내가 보낸"
    const val expand = "더 보기"
    const val collapse = "접기"
    const val adminHideAction = "내리기"
    const val adminHidden = "확성기를 내렸어요"
    const val adminForbidden = "운영자만 내릴 수 있어요"
    const val adminHideFailed = "내리지 못했어요. 다시 해 주세요"

    /** 받은 사람 수(작은 글씨 — "46명에게"). */
    fun recipients(count: Long): String = "${count}명에게"

    /** 줄의 시각("오늘 14:05" · "어제 09:12" · "11월 3일 18:40") — 메시지 날짜 구분선과 같은 말. */
    fun timeLabel(date: SwiftDate, now: SwiftDate, zone: TimeZone): String =
        "${MessageThreadBuilder.dayLabel(date.timeIntervalSince1970, now.timeIntervalSince1970, zone)} " +
            MessageThreadBuilder.clockText(date.timeIntervalSince1970, zone)
}

/** 지난 확성기 한 건(화면이 그리는 값). **배너(`MegaphoneBanner`)와 다른 타입이다**. */
data class MegaphoneFeedItem(
    /** 확성기 한 번(`megaphones.id`) — 줄의 정체(중복 지우기 · 운영자 내리기의 p_id). */
    val megaphoneID: String,
    val senderID: String?,
    val senderName: String,
    val senderAvatarURL: SwiftURL? = null,
    /** 서버가 머리말을 뗀 본문(정규화만 — 다시 떼지 않는다). */
    val body: String,
    val recipients: Long? = null,
    val createdAt: SwiftDate,
    /** 서버 정수 마이크로초 — 다음 쪽 커서. Long 그대로(실수로 바꾸면 µs 가 뭉개진다). */
    val createdEpochUs: Long,
    val isOwn: Boolean = false,
) {
    val id: String get() = megaphoneID
}

/** 한 쪽(도메인) — 최신이 먼저 · 쪽 안 중복 없음. */
data class MegaphoneFeedPage(val items: List<MegaphoneFeedItem>, val hasMore: Boolean)

object MegaphoneFeedDecode {
    /** 줄 → 도메인. id · 커서(µs)가 없거나 보이는 본문이 없으면 null(지어내지 않는다). [me] 는 서버가 is_mine 을 안 실었을 때만 쓴다. */
    fun item(row: MegaphoneFeedRow, me: String?): MegaphoneFeedItem? {
        val megaphoneID = nonEmpty(row.megaphoneId) ?: return null
        val cursor = row.createdEpochUs ?: return null
        if (cursor <= 0) return null
        val text = MessageBody.sanitized(row.body ?: "")
        if (!MessageBody.hasVisibleContent(text)) return null
        val millis = row.createdEpochMs ?: (cursor / 1000)
        val sender = nonEmpty(row.senderId)
        val name = (row.senderDisplayName ?: "").trim()
        val mine = nonEmpty(me)
        val own = row.isMine ?: (sender != null && mine != null && sender.lowercase() == mine.lowercase())
        return MegaphoneFeedItem(
            megaphoneID = megaphoneID,
            senderID = sender,
            senderName = name.ifEmpty { MegaphoneBanner.fallbackSenderName },
            senderAvatarURL = nonEmpty(row.senderAvatarUrl)?.let(SwiftURL::parse),
            body = text,
            recipients = row.recipients?.let { maxOf(0L, it) },
            createdAt = SwiftDate.fromEpochMillis(millis),
            createdEpochUs = cursor,
            isOwn = own,
        )
    }

    /** 응답(읽힌 줄 + 전선 줄 수) → 한 쪽. 가득 찼으면(전선 줄 수 ≥ 요청 수) 더 있다 — 깨진 줄도 센다(29줄로 보여 더 보기가 끊기지 않게). */
    fun page(rows: List<MegaphoneFeedRow>, wireRowCount: Int, limit: Int, me: String?): MegaphoneFeedPage {
        val seen = HashSet<String>()
        val items = rows.mapNotNull { item(it, me) }.filter { seen.add(it.id) }
        return MegaphoneFeedPage(items, hasMore = limit > 0 && wireRowCount >= limit)
    }

    private fun nonEmpty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }
}
