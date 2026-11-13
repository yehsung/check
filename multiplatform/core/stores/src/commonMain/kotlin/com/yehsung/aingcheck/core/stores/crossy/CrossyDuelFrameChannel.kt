// 원본: Sources/CheckCore/CrossyDuelFrameChannel.swift @ e4995a3a(판 표시 프레임 둘째 소켓) — Android 판 8
//
// 세 층(Swift 와 같다): ① [CrossyDuelFrameChannel] — 스토어가 보는 유일한 추상화(시험은 스텁) ② [CrossyDuelFrameWire] — 해석(순수)
// ③ 라이브 = [SocketCrossyDuelFrameChannel](글자 층 [BroadcastFrameSocket] 위에 선다 — Ktor 소켓은 core:net 에, 프레임 뜻은 여기).
// 지키는 것: 조인은 언제나 private · broadcast.self:false · ack:false · `poke:` 토픽에 싣지 않는다(`crossy_duel:` 밖은 열지 않는다) · REST 전송 없음.
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.realtime.BroadcastFrameSocket
import com.yehsung.aingcheck.core.net.realtime.BroadcastSocketEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.games.CrossyDuelFramesRow
import kotlinx.serialization.json.JsonObject

/** 프레임 소켓에서 올라오는 사건. */
sealed interface CrossyDuelFrameChannelEvent {
    /** 소켓·채널 사건. 장부의 `apply` 에 그대로 넣는다. */
    data class Transport(val event: RealtimeTransportEvent) : CrossyDuelFrameChannelEvent
    /** 모양을 통과한 상대 프레임 한 장. */
    data class Frame(val frame: CrossyDuelFrame) : CrossyDuelFrameChannelEvent
    /** 우리 토픽의 `frame` 이었지만 모양이 깨졌다(아무것도 바꾸지 않는다). */
    data class Rejected(val rejection: CrossyDuelFrameRejection) : CrossyDuelFrameChannelEvent
}

/** 판 표시 프레임 소켓의 **유일한** 추상화. 모든 메서드가 부수효과 명령이고 반환이 없다. */
interface CrossyDuelFrameChannel {
    var onEvent: ((CrossyDuelFrameChannelEvent) -> Unit)?
    /** 이 토픽으로 private join 을 연다. `crossy_duel:` 로 시작하지 않으면 열지 않고 Closed 를 낸다. */
    fun connect(projectURL: String, apiKey: String, accessToken: String, topic: String)
    fun send(event: String, payload: JsonObject)
    fun pushAccessToken(token: String)
    fun disconnect()
}

/** 해석(순수). 라이브 소켓과 시험 스텁이 같은 해석을 쓴다. */
object CrossyDuelFrameWire {
    /** broadcast 이름 · 본문 → 사건. 우리 이름(`frame`)이 아니면 null. */
    fun event(broadcastEvent: String, payload: JsonObject): CrossyDuelFrameChannelEvent? {
        if (broadcastEvent != CrossyDuelFrame.EVENT) return null
        return when (val decoded = CrossyDuelFrame.decode(payload)) {
            is CrossyDuelFrame.Decoded.Ok -> CrossyDuelFrameChannelEvent.Frame(decoded.frame)
            is CrossyDuelFrame.Decoded.Rejected -> CrossyDuelFrameChannelEvent.Rejected(decoded.rejection)
        }
    }

    /** 열어도 되는 토픽인가 — `crossy_duel:` 로 시작하고 그 뒤가 비지 않았다. */
    fun isFrameTopic(topic: String): Boolean =
        topic.startsWith(CrossyDuelFramesRow.TOPIC_PREFIX) && topic.length > CrossyDuelFramesRow.TOPIC_PREFIX.length
}

/** 진짜 소켓 위의 프레임 채널. 글자 층([socket])이 시험 프로세스에서 null 이면 이 채널도 만들어지지 않는다(조립 지점이 가른다). */
class SocketCrossyDuelFrameChannel(private val socket: BroadcastFrameSocket) : CrossyDuelFrameChannel {
    override var onEvent: ((CrossyDuelFrameChannelEvent) -> Unit)? = null

    init {
        socket.onEvent = { event ->
            when (event) {
                is BroadcastSocketEvent.Transport -> onEvent?.invoke(CrossyDuelFrameChannelEvent.Transport(event.event))
                is BroadcastSocketEvent.Broadcast -> CrossyDuelFrameWire.event(event.event, event.payload)?.let { onEvent?.invoke(it) }
            }
        }
    }

    override fun connect(projectURL: String, apiKey: String, accessToken: String, topic: String) {
        if (!CrossyDuelFrameWire.isFrameTopic(topic)) {
            socket.disconnect()
            onEvent?.invoke(CrossyDuelFrameChannelEvent.Transport(RealtimeTransportEvent.Closed(null)))
            return
        }
        socket.connect(projectURL, apiKey, accessToken, topic)
    }

    override fun send(event: String, payload: JsonObject) = socket.send(event, payload)
    override fun pushAccessToken(token: String) = socket.pushAccessToken(token)
    override fun disconnect() = socket.disconnect()
}
