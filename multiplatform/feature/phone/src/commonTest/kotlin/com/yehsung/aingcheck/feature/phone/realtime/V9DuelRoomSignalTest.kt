// 원본: Tests/CheckMobileKitTests/V1019DuelRoomsTests.swift(gameSignals) @ 9774e23b — 판 9 1:1 대기방
package com.yehsung.aingcheck.feature.phone.realtime

import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class V9DuelRoomSignalTest {
    /** 여섯 게임 초인종만 방 숨을 부른다(마작 · 큐브 · 확성기 · 메시지는 아니다). */
    @Test
    fun onlySixGameSignalsWakeTheRoomPing() {
        for (effect in listOf(RealtimeEffect.GomokuSignal, RealtimeEffect.ChessSignal, RealtimeEffect.TetrisSignal, RealtimeEffect.ReversiSignal,
            RealtimeEffect.CrossyDuelSignal, RealtimeEffect.AlkkagiSignal)) {
            assertTrue(PhoneRealtimeRunner.isDuelRoomGameSignal(effect), "$effect")
        }
        for (effect in listOf(RealtimeEffect.MahjongSignal, RealtimeEffect.RummySignal, RealtimeEffect.MegaphoneSignal, RealtimeEffect.Drain)) {
            assertFalse(PhoneRealtimeRunner.isDuelRoomGameSignal(effect), "$effect")
        }
    }
}
