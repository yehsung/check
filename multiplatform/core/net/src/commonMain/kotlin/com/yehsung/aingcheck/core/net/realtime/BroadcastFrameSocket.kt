// 원본: Sources/CheckCore/CrossyDuelFrameChannel.swift:79-217(LiveCrossyDuelFrameChannel) @ e4995a3a — Android 판 8
package com.yehsung.aingcheck.core.net.realtime

import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import io.ktor.client.HttpClient
import io.ktor.client.plugins.websocket.DefaultClientWebSocketSession
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlin.coroutines.cancellation.CancellationException

/** 판 표시 프레임 소켓에서 올라오는 사건(글자 층 — 프레임 본문의 뜻은 위층이 읽는다). */
sealed interface BroadcastSocketEvent {
    /** 소켓·채널 사건(열림 · join · 거절 · 닫힘 · 하트비트). */
    data class Transport(val event: RealtimeTransportEvent) : BroadcastSocketEvent
    /** 우리 토픽의 broadcast 한 건(이름 · 안쪽 본문). */
    data class Broadcast(val event: String, val payload: JsonObject) : BroadcastSocketEvent
}

/**
 * 판 표시 프레임 전용 **둘째 소켓**(Swift `CrossyDuelFrameChannel` 의 글자 층). 초인종 소켓([RealtimeTransport])과 따로 선다 —
 * 조인은 언제나 `private:true` · `broadcast.self:false` · `ack:false`(`RealtimeFrame.join`). REST 전송은 없다. 언제 열고 닫는지는
 * 이 층이 정하지 않는다(위층 장부가 정하고 스토어가 시킨다). 모든 메서드가 부수효과 명령이고 결과는 [onEvent] 로만 온다.
 */
interface BroadcastFrameSocket {
    var onEvent: ((BroadcastSocketEvent) -> Unit)?
    /** 이 토픽(접두사 없는 채널명)으로 private join 을 연다(이미 열려 있으면 닫고 새로 연다 — 세대가 바뀐다). */
    fun connect(projectURL: String, apiKey: String, accessToken: String, topic: String)
    /** join 된 채널에 broadcast 한 건. 열려 있지 않으면 버린다. */
    fun send(event: String, payload: JsonObject)
    /** 열린 채널에 새 토큰을 밀어 넣는다(판 중 세션 토큰이 바뀌었다). */
    fun pushAccessToken(token: String)
    fun disconnect()
}

/**
 * Ktor WebSocket 프레임 소켓(Swift `LiveCrossyDuelFrameChannel`). **시험 프로세스에서는 태어나지 못한다**([create] 가 null — 판정은
 * [KtorRealtimeTransport.create] 와 같은 [RunningTests] 하나). 초인종 소켓과 다른 자리 둘: ① 하트비트를 **스스로** 25초마다 보낸다
 * (다음 하트비트 때까지 답이 없으면 HeartbeatTimedOut 을 내고 멈춘다 — 장부가 lost 로 닫고 재시도 규칙을 탄다). ② 보내기가 있다.
 */
class KtorBroadcastFrameSocket private constructor(
    private val client: HttpClient,
    private val scope: CoroutineScope,
    private val heartbeatSeconds: Double,
) : BroadcastFrameSocket {
    override var onEvent: ((BroadcastSocketEvent) -> Unit)? = null

    private var session: DefaultClientWebSocketSession? = null
    private var job: Job? = null
    private var heartbeatJob: Job? = null
    private var topic: String? = null
    private var joinRef: String? = null
    private var refCounter = 0L
    private var pendingHeartbeat = false
    private var generation = 0L

    companion object {
        const val HEARTBEAT_SECONDS: Double = RealtimeLinkConstants.heartbeatIntervalSeconds

        /** 시험 프로세스면 **null**(fail-closed). 예외는 `CHECK_E2E=1` 뿐. 클라이언트는 [KtorRealtimeTransport.clientConfig] 로 만든 것. */
        fun create(
            client: HttpClient,
            scope: CoroutineScope,
            runningTests: RunningTests,
            environment: Map<String, String>,
            heartbeatSeconds: Double = HEARTBEAT_SECONDS,
        ): KtorBroadcastFrameSocket? {
            if (runningTests.isRunningTests && environment["CHECK_E2E"] != "1") return null
            return KtorBroadcastFrameSocket(client, scope, maxOf(1.0, heartbeatSeconds))
        }
    }

    override fun connect(projectURL: String, apiKey: String, accessToken: String, topic: String) {
        disconnect()
        generation += 1
        val gen = generation
        val socketURL = RealtimeFrame.socketURL(projectURL, apiKey)
        if (socketURL == null) {
            emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.Closed(null)), gen)
            return
        }
        this.topic = topic
        refCounter = 0
        pendingHeartbeat = false
        val ref = nextRef()
        joinRef = ref
        val joinFrame = RealtimeFrame.join(topic, accessToken, isPrivate = true, ref = ref)
        emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.Opened), gen)
        job = scope.launch {
            try {
                val s = client.webSocketSession(socketURL)
                if (gen != generation) {
                    s.close(CloseReason(CloseReason.Codes.GOING_AWAY, ""))
                    return@launch
                }
                session = s
                s.send(Frame.Text(joinFrame))
                startHeartbeat(gen)
                for (frame in s.incoming) {
                    if (gen != generation) break
                    val text = when (frame) {
                        is Frame.Text -> frame.readText()
                        is Frame.Binary -> frame.data.decodeToString()
                        else -> null
                    } ?: continue
                    val t = this@KtorBroadcastFrameSocket.topic ?: continue
                    val broadcast = RealtimeFrame.decodeBroadcastPayload(text, t)
                    if (broadcast != null) {
                        emit(BroadcastSocketEvent.Broadcast(broadcast.first, broadcast.second), gen)
                        continue
                    }
                    val event = RealtimeFrame.decode(text, t, joinRef) ?: continue
                    // 토픽 없는 broadcast(누구 판인지 모른다)는 버린다.
                    if (event is RealtimeTransportEvent.Broadcast) continue
                    if (event == RealtimeTransportEvent.HeartbeatAck) pendingHeartbeat = false
                    emit(BroadcastSocketEvent.Transport(event), gen)
                }
                emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.Closed(null)), gen)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.Closed(null)), gen)
            }
        }
    }

    override fun send(event: String, payload: JsonObject) {
        val t = topic ?: return
        val jr = joinRef ?: return
        send(RealtimeFrame.broadcast(t, event, payload, nextRef(), jr), generation)
    }

    override fun pushAccessToken(token: String) {
        val t = topic ?: return
        val jr = joinRef ?: return
        send(RealtimeFrame.accessToken(t, token, nextRef(), jr), generation)
    }

    override fun disconnect() {
        generation += 1
        val s = session
        heartbeatJob?.cancel()
        heartbeatJob = null
        job?.cancel()
        job = null
        session = null
        topic = null
        joinRef = null
        pendingHeartbeat = false
        if (s != null) scope.launch { try { s.close(CloseReason(CloseReason.Codes.GOING_AWAY, "")) } catch (e: Exception) { } }
    }

    private fun startHeartbeat(gen: Long) {
        heartbeatJob?.cancel()
        val intervalMs = (heartbeatSeconds * 1000).toLong()
        heartbeatJob = scope.launch {
            while (true) {
                delay(intervalMs)
                if (gen != generation || session == null) return@launch
                // 직전 하트비트가 답을 못 받았다 = half-open. 위층에 알리고 새로 보내지 않는다(닫기는 장부가 시킨다).
                if (pendingHeartbeat) {
                    emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.HeartbeatTimedOut), gen)
                    return@launch
                }
                pendingHeartbeat = true
                send(RealtimeFrame.heartbeat(nextRef()), gen)
            }
        }
    }

    private fun nextRef(): String {
        refCounter += 1
        return refCounter.toString()
    }

    private fun send(text: String, gen: Long) {
        if (gen != generation) return
        val s = session ?: return
        scope.launch {
            try {
                s.send(Frame.Text(text))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emit(BroadcastSocketEvent.Transport(RealtimeTransportEvent.Closed(null)), gen)
            }
        }
    }

    private fun emit(event: BroadcastSocketEvent, gen: Long) {
        if (gen != generation) return
        onEvent?.invoke(event)
    }
}
