// 원본: Sources/CheckCore/RealtimeLink.swift:130-136(reversiBroadcastEvent) · :532(`.reversiSignal` 가지) @ 12624739
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeLink
import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiWire
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 초인종 매핑(판 7). 없으면: 서버 `reversi__ring` 의 'reversi' 가 '모르는 이름'(Drain)으로 떨어져 수마다 메시지 조회가 한 번씩 더 나가고
 * 소켓은 판 상태를 한 번도 당기지 않는데도 초록이다. 이웃 가지(큐브 · 확성기 · 모르는 이름)는 그대로여야 한다.
 */
class RealtimeReversiSignalTest {
    private fun subscribedLink(): Pair<RealtimeLink, SwiftDate> {
        val link = RealtimeLink(transportAvailable = true)
        var now = SwiftDate(1_790_000_000.0)
        link.apply(RealtimeEvent.SignedIn("tok-1"), now) { it }
        for (e in listOf(RealtimeTransportEvent.Opened, RealtimeTransportEvent.Joined)) {
            now = now.addingTimeInterval(1.0)
            link.apply(RealtimeEvent.Transport(e), now) { it }
        }
        assertTrue(link.state is RealtimeState.Subscribed, "구독 상태가 아니다: ${link.state}")
        return link to now
    }

    @Test
    fun reversiBroadcastBecomesReversiSignal() {
        assertEquals(ReversiWire.broadcastEvent, RealtimeLinkConstants.reversiBroadcastEvent, "와이어 상수와 링 상수가 갈렸다")
        assertEquals("reversi", RealtimeLinkConstants.reversiBroadcastEvent)
        val (link, now) = subscribedLink()
        val table = listOf(
            "reversi" to listOf<RealtimeEffect>(RealtimeEffect.ReversiSignal),
            "rummy" to listOf<RealtimeEffect>(RealtimeEffect.RummySignal),
            "megaphone" to listOf<RealtimeEffect>(RealtimeEffect.MegaphoneSignal),
            "chess" to listOf<RealtimeEffect>(RealtimeEffect.ChessSignal),
            "ring" to listOf<RealtimeEffect>(RealtimeEffect.Drain),
        )
        var t = now
        for ((event, expected) in table) {
            t = t.addingTimeInterval(1.0)
            assertEquals(expected, link.apply(RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast(event)), t) { it }, event)
        }
    }
}
