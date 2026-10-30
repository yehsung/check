// W2-g2 · 공용 패치 3 — take_pokes 소비분을 진짜 MessagesStore 에 넣는 어댑터(조립이 쓴다). NoOpConsumedRowsSink 는 깃발 꺼짐·시험 자리.
// 원본: Sources/check/WorkTimerStoreMessagePokes.swift insertConsumedPokesIntoLog(106-150) · WorkTimerStoreMessages.swift:1022(대화 삽입 몫).
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.socialapi.ConsumedRowsSink

class MessagesStoreConsumedRowsSink(private val store: MessagesStore) : ConsumedRowsSink {
    override fun insertConsumedPokes(rows: List<TakenPokeRow>): Int = store.insertConsumedPokes(rows)

    override fun receiveConsumedMessages(rows: List<TakenPokeRow>, now: SwiftDate) = store.receiveConsumedMessages(rows, now)
}
