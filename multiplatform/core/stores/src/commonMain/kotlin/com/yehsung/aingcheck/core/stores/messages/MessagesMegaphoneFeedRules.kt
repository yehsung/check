// 원본: Sources/CheckMobileKit/Messages/MessagesMegaphoneFeedView.swift(MessagesMegaphoneFeedRules) @ 94975fa8 (폰 1.0.19 — 지난 확성기 줄의 순수 규칙)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedText
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.datetime.TimeZone

/** 신고 · 차단할 사람(지난 확성기 줄의 ··· 메뉴 대상). */
data class MegaphoneFeedActionTarget(val peerID: String, val peerName: String)

/** 지난 확성기 줄의 순수 규칙(맥 `MegaphoneFeedSafetyRule` · `metaText` · 아이폰과 같다 — 시험이 값으로 잰다). */
object MessagesMegaphoneFeedRules {
    /** 머리 줄 오른쪽의 작은 글씨: 시각 · 받은 사람 수(모르면 시각만). 폰 메시지 화면과 같은 KST 눈금. */
    fun metaText(item: MegaphoneFeedItem, now: SwiftDate, zone: TimeZone = MessagesTime.kst): String {
        val time = MegaphoneFeedText.timeLabel(item.createdAt, now, zone)
        val recipients = item.recipients
        if (recipients == null || recipients <= 0) return time
        return "$time · ${MegaphoneFeedText.recipients(recipients)}"
    }

    /** 신고 · 차단할 사람(내 글이거나 보낸 사람을 모르면 null — 나를 신고 · 차단하는 문은 없다). 서버가 is_mine 을 잘못 말해도 내 id 면 내 글. */
    fun actionTarget(item: MegaphoneFeedItem, me: String?): MegaphoneFeedActionTarget? {
        if (item.isOwn) return null
        val sender = item.senderID?.takeIf { it.isNotEmpty() } ?: return null
        if (me != null && sender.lowercase() == me.lowercase()) return null
        return MegaphoneFeedActionTarget(sender, item.senderName)
    }
}
