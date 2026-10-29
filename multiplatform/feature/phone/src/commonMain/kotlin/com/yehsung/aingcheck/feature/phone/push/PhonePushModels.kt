// 원본: Sources/CheckMobileKit/Push/PushPayload.swift(PushKind · PushPayload.Content · PushAction · PushPresentation · PushAuthorizationStatus ·
//       PushText) · Sources/CheckMobileKit/Push/PushNotificationSystem.swift @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.push

import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget

/**
 * 푸시 종류(서버 `push_outbox.kind` · `client_devices.push_prefs` 키와 같은 글자 — Android 채널 id 도 같다, K7).
 *
 * [workCheck] 는 **끌 수 없다**(서버 `set_push_prefs` 허용 목록 밖) — 그래서 나 탭 토글 목록([configurable])에서 빠진다.
 * [chessInvite] 는 Android 에만 있다(E§6.1 — iOS 는 아직 체스 신청 푸시가 없다). 앱 안 토글은 두지 않는다: 와이어 `PushPrefs` 가 세 칸
 * (message · gomoku_invite · feedback_reply)뿐이라 이 판에서 보내면 서버 칸을 지어내게 된다 — 시스템 채널로만 끈다(두 겹 스위치의 바깥쪽).
 */
enum class PhonePushKind(val rawValue: String, val settingTitle: String, val settingDetail: String) {
    message("message", "메시지", "누가 나에게 메시지를 보내면"),
    gomokuInvite("gomoku_invite", "오목 신청", "누가 오목 대결을 신청하면"),
    chessInvite("chess_invite", "체스 신청", "누가 체스 대결을 신청하면"),
    feedbackReply("feedback_reply", "제보 답장", "보낸 제보에 답장이 오면"),
    workCheck("work_check", "근무 확인", "폰으로 연 근무를 오래 확인하지 않으면");

    /** 지금 설정에서 켜져 있는가(끌 수 없는 종류는 늘 켜짐). */
    fun isEnabled(prefs: PushPrefs): Boolean = when (this) {
        message -> prefs.message
        gomokuInvite -> prefs.gomokuInvite
        feedbackReply -> prefs.feedbackReply
        chessInvite, workCheck -> true
    }

    /** 이 종류만 바꾼 설정(끌 수 없는 종류는 그대로). */
    fun setting(enabled: Boolean, prefs: PushPrefs): PushPrefs = when (this) {
        message -> prefs.copy(message = enabled)
        gomokuInvite -> prefs.copy(gomokuInvite = enabled)
        feedbackReply -> prefs.copy(feedbackReply = enabled)
        chessInvite, workCheck -> prefs
    }

    companion object {
        /** 나 탭에서 켜고 끌 수 있는 종류(서버 `set_push_prefs` 허용 목록 중 와이어가 싣는 셋 — Swift `configurable` 과 같은 순서). */
        val configurable: List<PhonePushKind> = listOf(message, gomokuInvite, feedbackReply)

        fun of(raw: String): PhonePushKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * 알림 한 건이 가리키는 것(Swift `PushPayload.Content`). FCM data 메시지(K7)의 판정은 셸의 `NotificationSpecs.decide`(W1-g)가 한다 —
 * 조립이 그 판정(게시 · 숨김)의 라우트를 이 값으로 옮겨 [PhonePushCoordinator.didReceive] 에 넘긴다(파서를 두 벌 두지 않는다).
 */
sealed interface PhonePushContent {
    data class Message(val peerID: String) : PhonePushContent
    data class GomokuInvite(val matchID: String) : PhonePushContent

    /** Android 에만(E§6.1). */
    data class ChessInvite(val matchID: String) : PhonePushContent

    /** null = 제보 목록. */
    data class FeedbackReply(val reportID: String?) : PhonePushContent

    /** 근무 확인(0.3.51). session_id 는 참고값이다 — 여는 곳은 언제나 지금 탭이다. */
    data class WorkCheck(val sessionID: String?) : PhonePushContent

    val kind: PhonePushKind
        get() = when (this) {
            is Message -> PhonePushKind.message
            is GomokuInvite -> PhonePushKind.gomokuInvite
            is ChessInvite -> PhonePushKind.chessInvite
            is FeedbackReply -> PhonePushKind.feedbackReply
            is WorkCheck -> PhonePushKind.workCheck
        }

    /** 알림을 눌렀을 때 여는 곳(Swift `PushPayload.route`). */
    val target: PhoneRouteTarget
        get() = when (this) {
            is Message -> PhoneRouteTarget.Message(peerID)
            is GomokuInvite -> PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite(matchID))
            is ChessInvite -> PhoneRouteTarget.ChessInvite(matchID)
            is FeedbackReply -> PhoneRouteTarget.Me(MeRoute.Feedback(reportID))
            is WorkCheck -> PhoneRouteTarget.Now
        }

    /** 메시지 알림이면 보낸 사람(대화 상대). */
    val messagePeerID: String? get() = (this as? Message)?.peerID
}

/** 사용자가 알림에 한 일(Swift `PushAction`). 앱을 열지 않고 도는 액션은 없다(w10 — 알림을 눌러 앱에서 한다). */
enum class PhonePushAction {
    /** 알림 본문을 눌렀다 · 모르는 액션 → 그 화면 열기. */
    open,

    /** 신청 알림 "수락"(앱을 연다 — 셸이 증표를 확인한 뒤 넘긴다). */
    acceptInvite,

    /** 알림 지우기 — 아무것도 하지 않는다. */
    dismiss,
}

/** 앞에서 알림이 왔을 때 보일지(Swift `PushPresentation`). */
enum class PhonePushPresentation { banner, hidden }

/**
 * 시스템 알림 권한(Swift `PushAuthorizationStatus` 의 Android 판). Android 13+ 는 `POST_NOTIFICATIONS` 런타임 권한(미결정 → 허락/거절),
 * 26~32 는 기본 허락이고 사용자가 앱 알림을 끄면 거절로 읽는다(`areNotificationsEnabled`). iOS 의 provisional·ephemeral 은 없다.
 */
enum class PhonePushAuthorization {
    /** 아직 읽지 않았다. */
    unknown,
    notDetermined,
    denied,
    authorized;

    /** 알림을 받을 수 있는가(토큰을 서버에 올릴 이유가 있는가). */
    val allowsDelivery: Boolean get() = this == authorized
}

/**
 * 푸시 조정자가 시스템(FCM · NotificationManager · 권한 창 · 설명 시트)에 시키는 일. Android 구현은 조립이 단다(androidApp — Firebase 는
 * 앱 모듈에만 있다). 시험은 기록하는 가짜가 구현한다 — 조정자는 Android 없이 JVM 시험으로 잰다(Swift 와 같은 구조).
 */
interface PhonePushSystem {
    /** 지금 알림 권한. */
    suspend fun authorizationStatus(): PhonePushAuthorization

    /** 시스템 권한 창을 띄운다(이미 답한 뒤면 창 없이 지금 값). 허락이면 true. API 26~32 는 창 없이 지금 값. */
    suspend fun requestAuthorization(): Boolean

    /** FCM 토큰을 받아 온다(`FirebaseMessaging.getToken`) — 결과는 [PhonePushCoordinator.didReceivePushToken] · [PhonePushCoordinator.didFailToRegister] 로 온다. */
    fun registerForRemoteNotifications()

    /** 이 설치의 FCM 토큰을 버린다(`deleteToken` — 로그아웃·치명 만료). 버린 토큰은 FCM 이 UNREGISTERED 로 거절해 서버 발송기가 비운다. */
    fun unregisterForRemoteNotifications()

    /** 알림 창에 남은 이 앱 알림을 모두 지운다(로그아웃한 앞 계정의 보낸 사람·본문이 남지 않게). */
    fun removeAllDeliveredNotifications()

    /** 앱 아이콘 숫자. Android 는 공식 API 가 없어(런처가 알림 수로 센다 — E§6.5) 구현이 비워 둘 수 있다. */
    fun setBadgeCount(count: Int)

    /** 시스템 설정의 이 앱 알림 화면. */
    fun openSystemSettings()

    /** 권한 설명 시트 띄우기 · 내리기(셸이 `NotificationPrimerSheet` 로 그린다). */
    fun presentPermissionPrimer()
    fun dismissPermissionPrimer()

    /** **우리가 띄우지 않은** 시스템 화면(로그인 직후 자동 채우기 저장 창)이 떠 있는가. 알 수 없는 플랫폼은 false. */
    val isSystemOverlayPresented: Boolean get() = false

    /** 그 화면이 뜨고 사라질 때 알려 달라(값이 바뀔 때만). 조정자가 필요한 동안만 켠다. */
    fun startObservingSystemOverlay(onChange: (Boolean) -> Unit) {}
    fun stopObservingSystemOverlay() {}
}

/** 푸시 화면 문구(Swift `PushText` — 설명 시트 · 나 탭 설정). */
object PhonePushText {
    const val acceptAction = "수락"

    const val primerTitle = "알림을 켜 둘까요?"
    const val primerBody = "앱을 닫아 두어도 이런 소식을 바로 알려 드려요."
    const val primerMacNote = "맥에서 근무 중이고 방금 입력이 있었다면 메시지·오목 신청 알림은 폰에 보내지 않아요."
    const val primerSettingsNote = "종류별로 끄는 것은 나 탭 설정에서 할 수 있어요."
    const val primerAllow = "알림 켜기"
    const val primerLater = "나중에"

    const val settingsAuthorized = "켜짐"
    const val settingsDenied = "꺼짐 — 설정에서 켤 수 있어요"
    const val settingsNotDetermined = "아직 켜지 않았어요"
    const val settingsUnknown = "확인 중"
    const val settingsOpenSystem = "설정 열기"
    const val settingsEnable = "알림 켜기"
    const val settingsSaveFailed = "알림 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요"
}
