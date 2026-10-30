// 원본: Sources/CheckCore/MegaphoneBanner.swift @ a6791165(b056075b) — 확성기 배너 도메인 · 표시 규칙 숫자 · megaphone_inbox 한 줄 디코드
// 계약: docs/plan/megaphone-banner-contract.md C1 · C2(2026-10-30 사용자 결정 — 메시지 한 줄 대신 화면 위에 크게)
//
// 서버는 지금처럼 받는 사람마다 `messages` 한 줄(`megaphone_id` 채움, 본문 앞 `📢 `)을 넣는다 — 옛 앱은 그대로 메시지로 받는다.
// 새 앱은 `megaphone_inbox(p_hours)` 가 돌려준 줄만 배너로 띄우고, 그 `message_id` 들만 메시지함에서 뺀다.
//
// ★ `📢 ` 접두는 표식이 아니다 — `send_message` 는 접두를 막지 않는다(아무나 `📢 안녕` 을 1:1 로 보낼 수 있다).
//   표식은 서버의 `messages.megaphone_id` 하나뿐이고, 클라가 그것을 아는 길은 `megaphone_inbox` 하나뿐이다.
//   그래서 이 파일의 어떤 판정도 본문 접두만 보고 숨기거나 띄우지 않는다(접두는 "확인해 볼 이유"일 뿐 — 스토어의 needsVerification).
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.swiftKeyed
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement

/** 화면에 뜨는 확성기 한 건(도메인). 폰 위 배너(· 맥 배너 패널)가 같은 값을 그린다. */
data class MegaphoneBanner(
    /** 내 메시지함의 그 줄(`messages.id`). 푸시로만 알고 아직 inbox 로 맞추기 전이거나 내가 보낸 배너면 null. */
    val messageID: String?,
    /** 확성기 한 번(`megaphones.id`) — 배너의 정체(같은 확성기는 한 번만 뜬다). 응답 id 없이 띄운 내 배너는 `local-` 로 시작하는 자리값. */
    val megaphoneID: String,
    /** 보낸 사람(답장 상대). 푸시로만 알고 아직 못 맞췄으면 null. */
    val senderID: String?,
    val senderName: String,
    val senderAvatarURL: String?,
    /** 접두(`📢 `)를 뗀 본문. */
    val body: String,
    val createdAt: SwiftDate,
    /** 내가 보낸 직후 띄우는 "이렇게 떴어요" 배너인가(답장 버튼이 없다). */
    val isOwn: Boolean = false,
) {
    val id: String get() = megaphoneID

    /** [답장] 을 보일 수 있는가 — 상대를 알고, 내가 보낸 것이 아닐 때. */
    val canReply: Boolean get() = !isOwn && !senderID.isNullOrEmpty()

    /** 같은 확성기의 더 나은 정보(inbox 가 푸시 자리값을 맞출 때)를 얹는다. 새 쪽에 값이 있으면 새 쪽이 이긴다. [isOwn] 은 처음 값을 지킨다. */
    fun merged(newer: MegaphoneBanner): MegaphoneBanner = MegaphoneBanner(
        messageID = newer.messageID ?: messageID,
        megaphoneID = megaphoneID,
        senderID = newer.senderID ?: senderID,
        senderName = newer.senderName.ifEmpty { senderName },
        senderAvatarURL = newer.senderAvatarURL ?: senderAvatarURL,
        body = newer.body.ifEmpty { body },
        createdAt = newer.createdAt,
        isOwn = isOwn,
    )

    companion object {
        /** 사람 이름이 비었을 때(서버 coalesce 와 같은 말). */
        const val fallbackSenderName = "사용자"

        /**
         * 화면에 그릴 본문: 정규화 후 앞의 `📢` 표식(뒤 공백 포함)을 한 번 뗀다. 보이는 글자가 없으면 null.
         * 푸시 알림 본문·내가 쓴 글·inbox 본문(서버가 이미 뗐다) 어느 것을 넣어도 같은 모양이 나온다.
         */
        fun displayBody(raw: String): String? {
            var text = MessageBody.sanitized(raw)
            // sanitized 가 앞뒤 공백을 이미 걷었다 — 표식은 맨 앞이다.
            if (hasMegaphonePrefix(text)) text = MessageBody.sanitized(text.substring(MegaphoneText.icon.length))
            return if (MessageBody.hasVisibleContent(text)) text else null
        }

        /** 본문이 `📢` 로 시작하는가(앞 공백은 건너뛴다). **표식이 아니다** — 확인해 볼 이유일 뿐(파일 머리 ★). */
        fun hasMegaphonePrefix(body: String): Boolean = TextScalars.trimmingWhitespacesAndNewlines(body).startsWith(MegaphoneText.icon)
    }
}

/** 배너 표시 규칙의 숫자(계약 C2). 화면·스토어·시험이 이 값 하나를 본다. */
object MegaphoneBannerRules {
    /** 신선도 — createdAt 이 이보다 오래된 것은 띄우지 않는다(켜 둔 사이 놓친 것은 보여 주되 묵은 것은 안 띄운다). */
    const val freshness: Double = 600.0

    /** 푸시를 눌러 들어온 항목은 이 안이면 신선도를 무시한다(24시간 — 서버 inbox 창과 같다). */
    const val pushWindow: Double = 24 * 3_600.0

    /** 한 장이 떠 있는 시간. */
    const val displaySeconds: Double = 8.0

    /** 닫힌 뒤 다음 장까지 쉬는 시간. */
    const val gap: Double = 0.4

    /** 멈췄다(누르고 있기) 풀리면 남은 시간과 이것 중 긴 쪽으로 다시 센다. */
    const val resumeMinimum: Double = 3.0

    /** 본 것 기록 — 계정별 최근 이만큼의 megaphoneID. */
    const val seenLimit: Int = 100

    /** `megaphone_inbox(p_hours)` 에 넘기는 창(서버가 1~24 로 자른다). */
    const val inboxHours: Int = 24

    /** 본 것 기록의 기본값 저장소 키(계정별 — 다음 계정에 새지 않는다). */
    fun seenKey(userID: String): String = "megaphoneBanner.seen.$userID"

    /** 지금 띄워도 되는가. 푸시로 들어온 것은 24시간, 나머지는 10분. 미래 시각(시계 어긋남)은 신선하다. */
    fun isPresentable(createdAt: SwiftDate, now: SwiftDate, fromPush: Boolean): Boolean =
        now.timeIntervalSince(createdAt) <= (if (fromPush) pushWindow else freshness)
}

/**
 * `megaphone_inbox` 응답 한 줄. 필수는 두 id 뿐이고 나머지는 옵셔널(메시지 파일 공통 규약 — 키 하나 빠진 서버에서 통째로 죽지 않게).
 * 보낸 사람 키는 `sender_id` 가 정본이고, 서버가 `from_user` 로 내려도 받는다.
 */
data class MegaphoneInboxItem(
    val messageId: String,
    val megaphoneId: String,
    val senderId: String? = null,
    val senderDisplayName: String? = null,
    val senderAvatarUrl: String? = null,
    val body: String? = null,
    val createdAt: String? = null,
    /** 초(정본). 밀리초로 와도 받는다(1e11 이 넘으면 밀리초로 본다 — 초로는 서기 5138년이다). */
    val createdEpoch: Double? = null,
) {
    /** 도메인으로. id 가 비었거나 · 보이는 본문이 없거나 · 시각을 모르면 null(지어내지 않는다). */
    fun banner(parseDate: (String) -> SwiftDate? = SwiftISO8601::parse): MegaphoneBanner? {
        if (messageId.isEmpty() || megaphoneId.isEmpty()) return null
        val text = MegaphoneBanner.displayBody(body ?: "") ?: return null
        val created = createdEpoch?.let { SwiftDate(if (it > 1e11) it / 1000 else it) } ?: createdAt?.let(parseDate) ?: return null
        val name = TextScalars.trimmingWhitespacesAndNewlines(senderDisplayName.orEmpty())
        return MegaphoneBanner(
            messageID = messageId,
            megaphoneID = megaphoneId,
            senderID = senderId?.ifEmpty { null },
            senderName = name.ifEmpty { MegaphoneBanner.fallbackSenderName },
            senderAvatarURL = senderAvatarUrl?.ifEmpty { null },
            body = text,
            createdAt = created,
        )
    }

    companion object {
        /** 한 줄. 필수 id 가 없거나 모양이 틀리면 던진다. */
        fun decode(element: JsonElement): MegaphoneInboxItem {
            val k: SwiftKeyed = swiftKeyed(element)
            return MegaphoneInboxItem(
                messageId = k.string("messageId"),
                megaphoneId = k.string("megaphoneId"),
                senderId = k.stringIfPresent("senderId") ?: k.stringIfPresent("fromUser"),
                senderDisplayName = k.stringIfPresent("senderDisplayName"),
                senderAvatarUrl = k.stringIfPresent("senderAvatarUrl"),
                body = k.stringIfPresent("body"),
                createdAt = k.stringIfPresent("createdAt"),
                createdEpoch = k.doubleIfPresent("createdEpoch"),
            )
        }

        /** 응답 배열 → 배너. 줄 하나가 깨져도(필수 id 없음) 나머지는 살린다. 배열이 아니면 던진다(해석 실패 = 연결 실패와 같은 취급). */
        fun banners(raw: JsonElement, parseDate: (String) -> SwiftDate? = SwiftISO8601::parse): List<MegaphoneBanner> {
            val rows = raw as? JsonArray ?: throw IllegalArgumentException("megaphone_inbox 응답이 배열이 아니다")
            return rows.mapNotNull { row -> runCatching { decode(row) }.getOrNull()?.banner(parseDate) }
        }
    }
}
