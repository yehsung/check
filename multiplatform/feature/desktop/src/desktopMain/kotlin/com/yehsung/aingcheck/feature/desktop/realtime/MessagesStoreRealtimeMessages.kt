// W2-g3 · 공용 패치 8 — 실시간 러너의 메시지 몫을 진짜 MessagesStore 에 잇는 어댑터(조립이 쓴다).
// 원본: Sources/check/WorkTimerStoreMessages.swift requestMessageActivityRefresh · requestMessageActivityRefreshCoalesced ·
// closeMessageActivityWindow. 창 타이머는 러너, 계기 번호와 "이미 맡았나" 판정은 스토어가 든다.
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.stores.messages.MessagesStore

class MessagesStoreRealtimeMessages(private val store: MessagesStore) : DesktopRealtimeMessages {
    override fun requestActivityRefresh() {
        store.requestActivityRefresh()
    }

    override fun readSignalArrived() = store.readSignalArrived()

    override fun readSignalWindowClosed() {
        store.readSignalWindowClosed()
    }
}
