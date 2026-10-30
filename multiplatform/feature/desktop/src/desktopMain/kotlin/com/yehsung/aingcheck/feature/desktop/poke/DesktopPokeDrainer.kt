// W2-g2 소비 몸 — Swift Sources/check/WorkTimerStorePoke.swift 581-665(drainReceivedPokes · requestDrain · flushPokesOnWorkEnd)
// · WorkTimerStoreMessages.swift:1022(receiveConsumedMessages 의 말풍선 몫) · S/WorkTimerStore.swift:2163-2175(꼬리 회수 호출부 계약).
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.poke.net.takePokes
import com.yehsung.aingcheck.feature.desktop.socialapi.ConsumedRowsSink
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.feature.desktop.socialapi.RealtimeSubscription
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPokeSink
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * take_pokes 소비의 **한 몸**(P6) — 폴링·꼬리·초인종·따라잡기가 공유한다(소비가 원자적이라 경로가 갈라지면 한쪽이 삼킨 찔림을 다른 쪽이 못 본다).
 *
 * 싱크([ReceivedPokeSink]·[ConsumedRowsSink])는 **생성자 필수**다 — 받는 쪽이 없으면 이 클래스를 조립하지 않고, 조립하지 않으면 take_pokes 도 없다
 * ([DesktopPokeWiring.drainerOrNull]). 받은 응답은 셋으로 갈린다: 찌르기 신선분 → [ReceivedPokeSink](ultra 는 강등된 채) ·
 * 메시지 → 보이는 대화([ConsumedRowsSink.receiveConsumedMessages]) + 말풍선 큐([bubbles]) · 찌르기 기록 → [ConsumedRowsSink.insertConsumedPokes].
 */
class DesktopPokeDrainer(
    private val host: SessionHost,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
    private val receivedSink: ReceivedPokeSink,
    private val consumedSink: ConsumedRowsSink,
    private val bubbles: DesktopMessageBubbleQueue,
    private val subscription: RealtimeSubscription,
    private val textRules: WireTextRules = RulesWireTextRules,
    /** Swift `isMessageAlreadyReadForBubble` — 이미 읽은 메시지는 말풍선으로 띄우지 않는다. 공용 패치 3(MessagesStore) 전 임시: 언제나 거짓. */
    private val isAlreadyReadForBubble: (QueuedBubbleMessage) -> Boolean = { false },
    /** take_pokes 한 번(시험 이음새). 기본은 [takePokes](P12 재호출 포함). */
    private val takePokesCall: suspend (accessToken: String) -> List<TakenPokeRow> = { token -> host.service.takePokes(token) },
) : PokeDrainer {
    private val lock = Any()
    private var drainInFlight: Job? = null
    private var drainPendingTrailing = false

    /** 시험이 완료를 기다리기 위한 것(돌고 있지 않으면 null). */
    val inFlight: Job? get() = synchronized(lock) { drainInFlight }

    /**
     * P6 Swift `drainReceivedPokes` — 세션 없으면 실패, 세대가 바뀌었으면 `.failed`(소비는 이미 서버에서 일어났다 — 성공으로 보고하면
     * 따라잡기가 새 계정의 미소비분을 놓친다). count 는 신선도로 거르기 **전** 행 수다(초인종 pending 과 견주는 값).
     */
    override suspend fun drainOnce(): DrainOutcome {
        if (host.session == null) return DrainOutcome.Failed("세션 없음")
        val generation = host.sessionGeneration
        val rows = try {
            host.withSessionRetry { session -> takePokesCall(session.accessToken) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            return DrainOutcome.Failed(e.toString())
        }
        if (generation != host.sessionGeneration) return DrainOutcome.Failed("세션 세대 변경")
        val now = clock()
        val batch = DesktopPokeRules.freshReceivedPokes(rows, now)
        if (batch.isNotEmpty()) receivedSink.onPokesReceived(batch)
        // 같은 응답이 갈리는 유일한 지점 — 메시지는 찔림 리액션을 타지 않고 자기 길로 간다(batch 에는 메시지가 없다).
        consumedSink.receiveConsumedMessages(rows, now)
        bubbles.append(DesktopPokeRules.freshReceivedMessages(rows, now, textRules).filterNot(isAlreadyReadForBubble))
        consumedSink.insertConsumedPokes(rows)
        return DrainOutcome.Ok(rows.size)
    }

    /**
     * ★ P7 Swift `requestDrain` — 직렬화. 이미 돌고 있으면 새로 쏘지 않고 트레일링 한 번으로 접는다.
     * defer 꼴(끝날 때 비우기)을 쓰지 않는다: 반복 **안에서 먼저** pending 을 내리고, '더 없음 확인 + 비우기'를 한 자물쇠 안에서 한다 —
     * 뒤에 내리면 이번 drain 이 도는 동안 도착한 신호를 지운다(두 번째 찌르기 유실).
     */
    override fun requestDrain() {
        synchronized(lock) {
            if (drainInFlight != null) {
                drainPendingTrailing = true
                return
            }
            drainInFlight = scope.launch(start = kotlinx.coroutines.CoroutineStart.LAZY) {
                while (true) {
                    synchronized(lock) { drainPendingTrailing = false }
                    drainOnce()
                    synchronized(lock) {
                        if (!drainPendingTrailing) {
                            drainInFlight = null
                            return@launch
                        }
                    }
                }
            }.also { job ->
                job.invokeOnCompletion { synchronized(lock) { if (drainInFlight === job) drainInFlight = null } }
            }
            drainInFlight
        }?.start()
    }

    /**
     * Swift `flushPokesOnWorkEnd` — 근무 종료 직후 꼬리 1회. **호출부 계약**: 사용자가 누른 stop 에서만. 종료 시퀀스([isTerminating])·
     * 자동 마감에서는 하지 않는다(응답 전에 프로세스가 죽으면 원자 소비된 찔림이 영구 소실). 세션이 없으면 null.
     * 구독 중이면서 억제 중이면 null — 지금은 억제가 없으므로(P11) 이 가드는 언제나 통과한다.
     */
    override fun flushOnUserStop(isTerminating: Boolean): Job? {
        if (isTerminating) return null
        if (host.session == null) return null
        if (DesktopPokeRules.pollingIsPausedByRealtime(subscription.isSubscribed)) return null
        return scope.launch { drainOnce() }
    }
}

/** 공용 패치 3 전 임시: MessagesStore.insertConsumedPokes·receiveConsumedMessages 가 들어오기 전까지 기록에는 쓰지 않는다(개수 0). 찌르기 표시는 그대로 간다. */
object NoOpConsumedRowsSink : ConsumedRowsSink {
    override fun insertConsumedPokes(rows: List<TakenPokeRow>): Int = 0
    override fun receiveConsumedMessages(rows: List<TakenPokeRow>, now: SwiftDate) {}
}

/** 조립 도움(AppGraph 가 부른다). 싱크가 하나라도 없으면 drainer 를 만들지 않는다 → 폴링이 take_pokes 를 부르지 않는다(위험 ①). */
object DesktopPokeWiring {
    fun drainerOrNull(
        host: SessionHost,
        scope: CoroutineScope,
        clock: () -> SwiftDate,
        receivedSink: ReceivedPokeSink?,
        consumedSink: ConsumedRowsSink?,
        bubbles: DesktopMessageBubbleQueue,
        subscription: RealtimeSubscription,
    ): DesktopPokeDrainer? {
        if (receivedSink == null || consumedSink == null) return null
        return DesktopPokeDrainer(host, scope, clock, receivedSink, consumedSink, bubbles, subscription)
    }
}
