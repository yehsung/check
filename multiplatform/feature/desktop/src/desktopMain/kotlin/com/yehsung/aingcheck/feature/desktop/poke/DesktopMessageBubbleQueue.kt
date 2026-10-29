// W2-g2 받은 메시지 말풍선 큐 — Swift Sources/check/WorkTimerStorePoke.swift 686-840(currentMessage · consumeCurrentMessage ·
// expireStaleMessages · expireLastShownMessage · appendToMessageBubbleQueue). 조정 ④: 큐와 상한 20·5분은 여기, '띄웠을 때만 소비'는 오버레이.
// ★ P13: 메시지 쿨타임 미러(messageCooldownUntil)는 **되살리지 않는다** — 서버가 send_message 에서 cooldown 을 영원히 내지 않는다.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.socialapi.MessageBubbleInbox
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class DesktopMessageBubbleQueue : MessageBubbleInbox {
    private val lock = Any()
    private val _queue = MutableStateFlow<List<QueuedBubbleMessage>>(emptyList())
    private val _lastShown = MutableStateFlow<QueuedBubbleMessage?>(null)

    /** 표시 대기 큐(맨 앞이 곧 화면). */
    val queue: StateFlow<List<QueuedBubbleMessage>> = _queue.asStateFlow()

    /** 표시가 끝나 큐에서 옮겨 담은 직전 메시지(팝오버 '놓친 것'). 1시간 지나면 버린다. */
    val lastShown: StateFlow<QueuedBubbleMessage?> = _lastShown.asStateFlow()

    override val current: QueuedBubbleMessage? get() = _queue.value.firstOrNull()

    /** 지금 것 뒤에 몇 건이 기다리는가. */
    val waitingCount: Int get() = maxOf(0, _queue.value.size - 1)

    /** 표시가 끝났다 — 버리지 않고 [lastShown] 으로 옮긴다. 큐가 비어 있으면 직전 표시분을 그대로 둔다. */
    override fun consumeCurrent() {
        synchronized(lock) {
            val q = _queue.value
            if (q.isEmpty()) return
            _lastShown.value = q.first()
            _queue.value = q.drop(1)
        }
    }

    /**
     * Swift `appendToMessageBubbleQueue` — 같은 id 는 무시(토큰 갱신 재발사 창의 중복), 상한을 넘으면 **오래된 쪽부터** 버린다.
     * 새로 붙은 것이 있으면 true.
     */
    fun append(messages: List<QueuedBubbleMessage>): Boolean {
        if (messages.isEmpty()) return false
        synchronized(lock) {
            val known = _queue.value.mapTo(HashSet()) { it.id }
            val arrivals = messages.filter { it.id !in known }
            if (arrivals.isEmpty()) return false
            var next = _queue.value + arrivals
            if (next.size > DesktopPokeRules.MESSAGE_QUEUE_LIMIT) next = next.drop(next.size - DesktopPokeRules.MESSAGE_QUEUE_LIMIT)
            _queue.value = next
            return true
        }
    }

    /** 표시를 기다리다 5분(300초 초과)이 지난 메시지를 큐에서 버린다(알리지 않는다). 버릴 게 없으면 대입하지 않는다. */
    fun expireStale(now: SwiftDate) {
        synchronized(lock) {
            val q = _queue.value
            if (q.isEmpty()) return
            val fresh = q.filter { now.timeIntervalSince(it.createdAt) <= DesktopPokeRules.MESSAGE_DISPLAY_FRESHNESS_SECONDS }
            if (fresh.size != q.size) _queue.value = fresh
        }
    }

    /** '최근 표시 메시지'는 **1시간**(3600 초과)이 지나면 버린다 — 위 5분과 다른 상수인 것이 의도다. */
    fun expireLastShown(now: SwiftDate) {
        synchronized(lock) {
            val last = _lastShown.value ?: return
            if (now.timeIntervalSince(last.createdAt) > DesktopPokeRules.POKE_DISPLAY_FRESHNESS_SECONDS) _lastShown.value = null
        }
    }

    /** 로그아웃(앞 계정의 말풍선을 새 계정에 띄우지 않는다). */
    fun reset() {
        synchronized(lock) {
            _queue.value = emptyList()
            _lastShown.value = null
        }
    }
}
