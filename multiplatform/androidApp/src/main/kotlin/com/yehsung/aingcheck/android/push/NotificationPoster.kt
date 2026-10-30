// 알림 사양 → 시스템 알림. E§6.5:
// - 탭은 PendingIntent.getActivity(Android 12+ 트램펄린 금지 — 수신기·서비스에서 Activity 를 띄우지 않는다), FLAG_IMMUTABLE.
// - 여는 Intent 는 MainActivity 를 가리키는 명시적 Intent + 라우트 extra(RouteIntents). MainActivity 는 singleTask 라
//   떠 있으면 onNewIntent 로 받는다(E-U16).
// - [수락] 은 Activity 를 직접 열고 수락 증표(RouteProof)를 싣는다 — 다른 앱이 수락을 흉내 내지 못하게.
//   확성기 탭도 같은 증표를 싣는다 — 다른 앱이 지어낸 보낸 사람 · 본문으로 앱 배너를 띄우지 못하게.
// - 알림 권한이 꺼져 있으면 게시하지 않는다(시스템이 어차피 버린다 — 예외 대신 조용히).
package com.yehsung.aingcheck.android.push

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.yehsung.aingcheck.android.R
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest

class NotificationPoster(
    private val context: Context,
    /** 수락 증표. 못 만들면 null — 그때는 [수락] 버튼을 싣지 않는다. */
    private val acceptProof: () -> String?,
) {
    /** 게시했으면 true. 권한이 없거나 채널이 막혀 있으면 false. */
    @SuppressLint("MissingPermission") // areNotificationsEnabled() 로 먼저 거른다(API 33+ 권한 거부면 false).
    fun post(spec: NotificationSpec): Boolean {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return false
        val proof = if (spec.actions.any { it.request.accept } || spec.tap.megaphone != null) acceptProof() else null
        val builder = NotificationCompat.Builder(context, spec.channel.id)
            // 앱 알림 아이콘 = 아잉이 실루엣(흰 단색 · 눈 구멍) + accent 색(알림 머리의 아이콘 · 앱 이름 색).
            .setSmallIcon(SMALL_ICON)
            .setColor(ContextCompat.getColor(context, ACCENT_COLOR))
            .setContentTitle(spec.title)
            .setContentText(spec.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(spec.body))
            .setCategory(spec.category)
            .setPriority(if (spec.channel.importance == ChannelImportance.HIGH) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent(spec.tap, proof = if (spec.tap.megaphone != null) proof else null, requestCode = requestCode(spec.tag, 0)))
        spec.group?.let { builder.setGroup(it) }
        spec.actions.forEachIndexed { index, action ->
            if (action.request.accept && proof == null) return@forEachIndexed // 증표 없이 수락 버튼을 만들지 않는다
            builder.addAction(
                NotificationCompat.Action.Builder(0, action.title, pendingIntent(action.request, proof, requestCode(spec.tag, index + 1))).build(),
            )
        }
        manager.notify(spec.tag, NOTIFICATION_ID, builder.build())
        spec.group?.let { group -> postGroupSummary(manager, spec, group) }
        return true
    }

    @SuppressLint("MissingPermission")
    private fun postGroupSummary(manager: NotificationManagerCompat, spec: NotificationSpec, group: String) {
        val summary = NotificationCompat.Builder(context, spec.channel.id)
            .setSmallIcon(SMALL_ICON)
            .setColor(ContextCompat.getColor(context, ACCENT_COLOR))
            .setContentTitle(spec.channel.title)
            .setGroup(group)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .setCategory(spec.category)
            .build()
        manager.notify("$group-summary", NOTIFICATION_ID, summary)
    }

    private fun pendingIntent(request: RouteRequest, proof: String?, requestCode: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            requestCode,
            RouteIntents.explicit(context, request, proof),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    companion object {
        /** 알림은 태그로 가른다(같은 태그 = 교체). id 는 하나로 둔다. */
        const val NOTIFICATION_ID = 1

        /** 상태 표시줄 · 알림 머리 아이콘(res/drawable/ic_stat_aing.xml — 시스템은 알파만 본다). FCM 기본 알림 아이콘도 같은 그림(매니페스트). */
        val SMALL_ICON: Int = R.drawable.ic_stat_aing

        /** 알림 강조색 = AingPalette.accent(라이트 #1864CF · 다크 values-night). */
        val ACCENT_COLOR: Int = R.color.aing_notification_accent

        /** 태그·버튼마다 다른 요청 번호(같으면 FLAG_UPDATE_CURRENT 가 다른 알림의 extra 를 덮는다). */
        fun requestCode(tag: String, slot: Int): Int = tag.hashCode() * 31 + slot
    }
}
