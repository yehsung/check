// 원본: Sources/CheckCore/MessagePokeLog.swift:169-179(MessageConversationLoad) @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageEntryFacts
import com.yehsung.aingcheck.core.rules.text.MessageHistoryLoad
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessageHistoryWithPokes
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry

/*
 * 메시지 스토어가 전선(W1-d)과 규칙(W1-c)을 엮는 자리(배정표 round5-lane-map.md:133).
 *
 * W1-c 는 이력 규칙을 [MessageEntryFacts] 를 받는 **제네릭**으로 옮겼고(core/rules 는 core/wire 의 행 타입을 감쌀 수 없다), W1-d 는
 * 조회 결과를 [MessageHistoryWithPokes](메시지 · 찌르기 · 서버 순위)로 준다. 둘을 잇는 묶음 타입([MessageConversationLoad])과 감싸개
 * ([MessageEntry])는 둘 다 볼 수 있는 이 층(core/stores)에만 설 수 있다.
 */

/** 전선 이력 한 줄을 규칙이 읽는 모양으로 감싼다. 규칙이 돌려준 목록은 이 타입 그대로라 [wire] 로 되돌아간다. */
data class MessageEntry(val wire: MessageHistoryEntry) : MessageEntryFacts {
    override val id: String get() = wire.id
    override val peerUserID: String get() = wire.peerUserID
    override val peerName: String get() = wire.peerName
    override val peerAvatarURL: String? get() = wire.peerAvatarURL?.absoluteString
    override val isMine: Boolean get() = wire.isMine
    override val isUnread: Boolean? get() = wire.isUnread

    /** 1970 기준 초(규칙의 눈금). 원래 날짜는 [createdDate]. */
    override val createdAt: Double get() = wire.createdAt.timeIntervalSince1970

    val createdDate: SwiftDate get() = wire.createdAt
    val body: String get() = wire.body
    val readByPeer: Boolean? get() = wire.readByPeer
    val avatarURL: SwiftURL? get() = wire.peerAvatarURL
}

/**
 * 이력 조회 한 번의 결과(Swift `MessageConversationLoad`). `pokes == null` 이면 **서버가 찌르기 기록을 모른다**(옛 조회로 접었다) —
 * 빈 배열(찌르기가 없다)과 다른 사실이다. [chronology] 는 행 id → 서버 시각 순위(메시지·찌르기 공통).
 */
data class MessageConversationLoad(
    val history: MessageHistoryLoad<MessageEntry>,
    val pokes: List<MessagePokeLogEntry>?,
    val chronology: Map<String, Int> = emptyMap(),
) {
    companion object {
        /** 새 조회(`message_history_with_pokes`)의 결과 → 묶음. 메시지는 읽음 칸을 싣는다(`hasReadReceipts = true`). */
        fun of(combined: MessageHistoryWithPokes): MessageConversationLoad = MessageConversationLoad(
            history = MessageHistoryLoad(combined.messages.map(::MessageEntry), hasReadReceipts = true),
            pokes = combined.pokes,
            chronology = combined.chronology.mapValues { it.value.toInt() },
        )

        /** 옛 조회로 접은 결과(찌르기를 모른다). */
        fun legacy(entries: List<MessageHistoryEntry>, hasReadReceipts: Boolean): MessageConversationLoad =
            MessageConversationLoad(MessageHistoryLoad(entries.map(::MessageEntry), hasReadReceipts), pokes = null)
    }
}
