// 원본: Sources/CheckCore/RealtimeTransport.swift:15-28·191-316(RealtimeTransport · LiveRealtimeTransport) @ 1b8260d
package com.yehsung.aingcheck.core.net.realtime

import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import io.ktor.client.plugins.websocket.DefaultClientWebSocketSession
import io.ktor.client.plugins.websocket.WebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.websocket.CloseReason
import io.ktor.websocket.Frame
import io.ktor.websocket.close
import io.ktor.websocket.readText
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * 실시간 전송자(Swift `RealtimeTransport` 프로토콜). 사건은 [onEvent] 로 — **같은 단일 스레드 범위**(앱은 Main)에서 부르고 받는다.
 * supabase-kt 를 쓰지 않는다(§8-1 #14 — Ktor + OkHttp WebSocket 직접).
 */
interface RealtimeTransport {
    var onEvent: ((RealtimeTransportEvent) -> Unit)?
    fun connect(projectURL: String, apiKey: String, accessToken: String, channel: String, isPrivate: Boolean)
    fun pushAccessToken(token: String)
    fun sendHeartbeat()
    fun disconnect()
}

/**
 * Ktor WebSocket 전송자(Swift `LiveRealtimeTransport`). HTTP 엔진은 앱의 단일 팩토리가 만든 클라이언트를 받는다
 * (`HttpEngineFactory.ktorClient(KtorRealtimeTransport.clientConfig)` — 재전송 끔, G §8-12).
 *
 * 세대(generation): disconnect 뒤에도 살아 있는 수신 루프가 **다음 연결의 상태를 흔드는 것**이 이 층의 가장 흔한 결함이라
 * 사건마다 세대를 견준다.
 */
class KtorRealtimeTransport private constructor(
    private val client: HttpClient,
    private val scope: CoroutineScope,
) : RealtimeTransport {
    override var onEvent: ((RealtimeTransportEvent) -> Unit)? = null

    private var session: DefaultClientWebSocketSession? = null
    private var job: Job? = null
    private var channel: String? = null
    private var joinRef: String? = null
    private var refCounter = 0L
    private var pendingHeartbeat = false
    private var generation = 0L

    companion object {
        /** 클라이언트에 붙일 설정(WebSockets). */
        val clientConfig: HttpClientConfig<*>.() -> Unit = { install(WebSockets) }

        /**
         * INV-RealtimeTransport-7605b829 이식: 시험 프로세스면 **null**(fail-closed — C§4 #17). 판정은 주입한 [RunningTests] 한 곳이고
         * 여기에 둘째 판정을 심지 않는다. 예외는 `CHECK_E2E=1`(localhost 왕복 시험처럼 일부러 실소켓을 여는 자리)뿐.
         */
        fun create(
            client: HttpClient,
            scope: CoroutineScope,
            runningTests: RunningTests,
            environment: Map<String, String>,
        ): KtorRealtimeTransport? {
            if (runningTests.isRunningTests && environment["CHECK_E2E"] != "1") return null
            return KtorRealtimeTransport(client, scope)
        }
    }

    override fun connect(projectURL: String, apiKey: String, accessToken: String, channel: String, isPrivate: Boolean) {
        disconnect()
        generation += 1
        val gen = generation
        val socketURL = RealtimeFrame.socketURL(projectURL, apiKey)
        if (socketURL == null) {
            emit(RealtimeTransportEvent.Closed(null), gen)
            return
        }
        this.channel = channel
        refCounter = 0
        pendingHeartbeat = false
        val ref = nextRef()
        joinRef = ref
        val joinFrame = RealtimeFrame.join(channel, accessToken, isPrivate, ref)
        emit(RealtimeTransportEvent.Opened, gen)
        job = scope.launch {
            try {
                val s = client.webSocketSession(socketURL)
                if (gen != generation) {
                    s.close(CloseReason(CloseReason.Codes.GOING_AWAY, ""))
                    return@launch
                }
                session = s
                s.send(Frame.Text(joinFrame))
                for (frame in s.incoming) {
                    if (gen != generation) break
                    val text = when (frame) {
                        is Frame.Text -> frame.readText()
                        is Frame.Binary -> frame.data.decodeToString()
                        else -> null
                    } ?: continue
                    val ch = channel ?: continue
                    val event = RealtimeFrame.decode(text, ch, joinRef) ?: continue
                    if (event == RealtimeTransportEvent.HeartbeatAck) pendingHeartbeat = false
                    emit(event, gen)
                }
                emit(RealtimeTransportEvent.Closed(null), gen)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emit(RealtimeTransportEvent.Closed(null), gen)
            }
        }
    }

    override fun pushAccessToken(token: String) {
        val ch = channel ?: return
        val jr = joinRef ?: return
        send(RealtimeFrame.accessToken(ch, token, nextRef(), jr), generation)
    }

    /** 앞 하트비트의 답이 아직 없으면 보내지 않고 무응답을 알린다(링이 끊고 다시 붙는다). */
    override fun sendHeartbeat() {
        if (job == null) return
        if (pendingHeartbeat) {
            emit(RealtimeTransportEvent.HeartbeatTimedOut, generation)
            return
        }
        pendingHeartbeat = true
        send(RealtimeFrame.heartbeat(nextRef()), generation)
    }

    override fun disconnect() {
        generation += 1
        val s = session
        job?.cancel()
        job = null
        session = null
        channel = null
        joinRef = null
        pendingHeartbeat = false
        if (s != null) scope.launch { try { s.close(CloseReason(CloseReason.Codes.GOING_AWAY, "")) } catch (e: Exception) { } }
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
                emit(RealtimeTransportEvent.Closed(null), gen)
            }
        }
    }

    private fun emit(event: RealtimeTransportEvent, gen: Long) {
        if (gen != generation) return
        onEvent?.invoke(event)
    }
}
