// 원본: Sources/CheckMobileKit/Push/PushPayload.swift · PushCoordinator.swift(포그라운드 표시 규칙) @ ios-1011(988609b)
// FCM data 전용 메시지(K7) → 알림 사양. **순수 함수**다(E§6.3) — Android 없이 JVM 시험이 페이로드 정본
// (contract/push/payloads, 서버 트리거 실출력)을 넣어 잰다. 게시·PendingIntent 는 NotificationPoster 가 한다.
//
// 규칙
// - data 키는 `type` · 각 id · `title` · `body` · `category` · `thread_id`, 값은 전부 문자열(K7).
// - 모르는 `type` · 필수 id 가 없거나 모양이 틀림 → **게시하지 않는다**(Swift PushPayload: 조용히 "지금"으로 접지 않는다).
// - id 는 다듬고 소문자로(서버 uuid, PushPayload.safeID). 라우트 id 규칙과 같다(영문·숫자·`-`·`_`, 1~64자).
// - 앞에서 **보고 있는 대화**의 메시지는 숨긴다(PushCoordinator 2). 다른 종류는 앞이어도 게시한다(헤즈업).
// - 체스 신청(chess_invite)은 iOS 에 아직 없고 Android 는 처리한다(E§6.1). 새 kind 는 만들지 않는다.
// - 짧은 실행 창 안에서 끝낸다: 이 판정은 네트워크·디스크를 쓰지 않는다.
package com.yehsung.aingcheck.android.push

import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteRequest

/** 알림 버튼 하나. 누르면 앱을 연다(앱을 열지 않는 액션은 두지 않는다 — iOS w10 결정). */
data class NotificationActionSpec(val id: String, val title: String, val request: RouteRequest)

/** 게시할 알림 한 건(플랫폼 무관 설명). */
data class NotificationSpec(
    val channel: AingChannel,
    val title: String,
    val body: String,
    /** 같은 태그면 앞 알림을 갈아 끼운다(상대별 메시지 · 판별 신청 · 근무 확인 하나). */
    val tag: String,
    /** 묶음(메시지만 — 상대별 알림을 한 덩이로). */
    val group: String?,
    /** 본문을 누르면 여는 화면. */
    val tap: RouteRequest,
    val actions: List<NotificationActionSpec>,
    /** android.app.Notification.CATEGORY_* 값. */
    val category: String,
)

/** 받은 data 메시지로 할 일. 셋 다 [refresh] 로 "그 스토어를 다시 읽어라"를 알린다(W2-f 가 쓴다). */
sealed interface PushDecision {
    data class Post(val spec: NotificationSpec, val refresh: AingChannel) : PushDecision
    /** 앞에서 그 대화를 보고 있다 — 게시하지 않고 대화만 다시 읽는다. */
    data class Hide(val route: AingRoute, val refresh: AingChannel) : PushDecision
    /** 게시하지 않는다(모르는 type · id 없음 · 모양 틀림). */
    data class Drop(val reason: String) : PushDecision
}

object NotificationSpecs {
    /** 신청 알림 [수락] 버튼 식별자(iOS PushIdentifiers.acceptAction 과 같은 글자). */
    const val ACCEPT_ACTION_ID = "GOMOKU_ACCEPT"
    const val ACCEPT_ACTION_TITLE = "수락"
    const val MESSAGE_GROUP = "message"

    // android.app.Notification.CATEGORY_* (상수 값을 글자로 — 순수 시험용).
    const val CATEGORY_MESSAGE = "msg"
    const val CATEGORY_SOCIAL = "social"
    const val CATEGORY_REMINDER = "reminder"

    /**
     * [data] = RemoteMessage.data. [viewing] = 앱이 앞일 때 보고 있는 라우트(뒤면 null).
     */
    fun decide(data: Map<String, String>, viewing: AingRoute?): PushDecision {
        val rawType = data["type"]?.trim()?.lowercase() ?: return PushDecision.Drop("type 없음")
        val channel = AingChannel.fromId(rawType) ?: return PushDecision.Drop("모르는 type '$rawType'")
        val title = data["title"]?.takeIf { it.isNotBlank() } ?: channel.title
        val body = data["body"].orEmpty()
        return when (channel) {
            AingChannel.MESSAGE -> {
                val peer = safeId(data["peer_id"]) ?: return PushDecision.Drop("message 에 peer_id 가 없거나 모양이 틀렸다")
                val route = AingRoute.Message(peer)
                if (viewing == route) return PushDecision.Hide(route, channel)
                post(channel, title, body, tag = "message-$peer", group = MESSAGE_GROUP, route = route, CATEGORY_MESSAGE)
            }
            AingChannel.GOMOKU_INVITE -> {
                val match = safeId(data["match_id"]) ?: return PushDecision.Drop("gomoku_invite 에 match_id 가 없거나 모양이 틀렸다")
                invite(channel, title, body, tag = "gomoku-$match", route = AingRoute.GomokuInvite(match))
            }
            AingChannel.CHESS_INVITE -> {
                val match = safeId(data["match_id"]) ?: return PushDecision.Drop("chess_invite 에 match_id 가 없거나 모양이 틀렸다")
                invite(channel, title, body, tag = "chess-$match", route = AingRoute.ChessInvite(match))
            }
            AingChannel.FEEDBACK_REPLY -> {
                // report_id 가 없으면 제보 목록으로 연다(Swift 와 같다). 모양이 틀린 id 도 목록으로 접는다.
                val report = safeId(data["report_id"])
                post(channel, title, body, tag = "feedback-${report ?: "list"}", group = null,
                    route = AingRoute.Feedback(report), CATEGORY_SOCIAL)
            }
            AingChannel.WORK_CHECK ->
                // session_id 는 참고값이다 — 여는 곳은 언제나 지금 탭. 앱을 여는 것 자체가 '아직 근무 중'이라는 답이다.
                post(channel, title, body, tag = "work-check", group = null, route = AingRoute.Now, CATEGORY_REMINDER)
        }
    }

    private fun post(
        channel: AingChannel,
        title: String,
        body: String,
        tag: String,
        group: String?,
        route: AingRoute,
        category: String,
    ): PushDecision = PushDecision.Post(
        NotificationSpec(channel, title, body, tag, group, RouteRequest(route), actions = emptyList(), category),
        refresh = channel,
    )

    private fun invite(channel: AingChannel, title: String, body: String, tag: String, route: AingRoute): PushDecision =
        PushDecision.Post(
            NotificationSpec(
                channel, title, body, tag, group = null,
                tap = RouteRequest(route),
                actions = listOf(NotificationActionSpec(ACCEPT_ACTION_ID, ACCEPT_ACTION_TITLE, RouteRequest(route, accept = true))),
                category = CATEGORY_SOCIAL,
            ),
            refresh = channel,
        )

    /** PushPayload.safeID: 다듬고, 1~64자 영문·숫자·`-`·`_` 이면 소문자로. */
    fun safeId(raw: String?): String? {
        val trimmed = raw?.trim() ?: return null
        return AingRoute.safeId(trimmed)?.lowercase()
    }
}
