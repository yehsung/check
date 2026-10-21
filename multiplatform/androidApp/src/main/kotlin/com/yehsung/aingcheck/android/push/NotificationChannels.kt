// 원본: Sources/CheckMobileKit/Push/PushPayload.swift(PushKind 이름·문구) @ ios-1011(988609b) — E§6.5 채널 표
// 채널 id 5개는 서버·push-send 와 맺은 계약이다(K7: 앱이 data.type 으로 고른다). 이름을 바꾸면 사용자가 꺼 둔 채널 설정이 사라진다.
// work_check 는 끌 수 없다(서버 set_push_prefs 허용 목록 밖) — 앱 안 토글 키가 없다. 시스템 채널은 사용자가 끌 수 있다(두 겹 스위치, E§6.5).
package com.yehsung.aingcheck.android.push

import android.content.Context
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationManagerCompat

/** 알림 중요도(android.app.NotificationManager.IMPORTANCE_* 와 같은 값 — 순수 시험이 Android 없이 닿게 숫자로 둔다). */
enum class ChannelImportance(val value: Int) {
    DEFAULT(3),
    HIGH(4),
}

/** 푸시 종류 = 채널(서버 push_outbox.kind · client_devices.push_prefs 키와 같은 글자). */
enum class AingChannel(
    val id: String,
    val title: String,
    val description: String,
    val importance: ChannelImportance,
    /** 앱 안 토글이 보내는 `set_push_prefs` 키. null = 끌 수 없다(work_check). */
    val prefsKey: String?,
) {
    MESSAGE("message", "메시지", "누가 나에게 메시지를 보내면", ChannelImportance.HIGH, "message"),
    GOMOKU_INVITE("gomoku_invite", "오목 신청", "누가 오목 대결을 신청하면", ChannelImportance.HIGH, "gomoku_invite"),
    CHESS_INVITE("chess_invite", "체스 신청", "누가 체스 대결을 신청하면", ChannelImportance.HIGH, "chess_invite"),
    FEEDBACK_REPLY("feedback_reply", "제보 답장", "보낸 제보에 답장이 오면", ChannelImportance.DEFAULT, "feedback_reply"),
    WORK_CHECK("work_check", "근무 확인", "폰으로 연 근무를 오래 확인하지 않으면", ChannelImportance.HIGH, null);

    companion object {
        fun fromId(id: String): AingChannel? = entries.firstOrNull { it.id == id }
    }
}

object NotificationChannels {
    /** 채널 다섯을 만든다(멱등 — 같은 id 로 다시 만들면 이름·설명만 갱신되고 사용자가 바꾼 중요도는 남는다). */
    fun ensure(context: Context) {
        val manager = NotificationManagerCompat.from(context)
        manager.createNotificationChannelsCompat(
            AingChannel.entries.map { channel ->
                NotificationChannelCompat.Builder(channel.id, channel.importance.value)
                    .setName(channel.title)
                    .setDescription(channel.description)
                    .setShowBadge(true)
                    .build()
            },
        )
    }

    /** 시스템에서 꺼진 채널인가(설정 행의 "시스템에서 꺼짐 → 설정 열기", E§6.5). 채널이 없으면 null. */
    fun isBlockedBySystem(context: Context, channel: AingChannel): Boolean? =
        NotificationManagerCompat.from(context).getNotificationChannelCompat(channel.id)?.let {
            it.importance == NotificationManagerCompat.IMPORTANCE_NONE
        }
}
