// W2-g2 찌르기 규칙 — Swift Sources/check/WorkTimerStorePoke.swift 1-64(상수·문구) · 366-372(쿨타임) · 456-475(주기·억제)
// · 668-684(freshReceivedPokes) · 686-807(말풍선 상수·freshReceivedMessages). 순수 함수만 — 상태는 각 클래스가 갖는다.
// 골든: contract/golden/desktop-poke/{fresh,send-notice}.json.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import kotlin.math.ceil
import kotlin.math.max

object DesktopPokeRules {
    /** 링 **미구독** 폴링 주기(초). */
    const val POLL_INTERVAL_SECONDS: Double = 15.0
    /** 링 **구독 중** 폴링 주기(초) — 안전망 지연 상한(v0.2.38 Q8). 지우거나 합치지 않는다. */
    const val POLL_INTERVAL_SECONDS_WHILE_SUBSCRIBED: Double = 60.0
    /** 찔림 표시 신선도(초) · '최근 표시 메시지' 보관 창. */
    const val POKE_DISPLAY_FRESHNESS_SECONDS: Double = 3600.0
    /** 같은 대상 쿨타임(초) — 서버가 강제하고 클라는 카운트다운만 미러링한다. */
    const val COOLDOWN_SECONDS: Double = 60.0
    /** 울트라 표시 신선도(초) — 넘으면 normal 로 **강등**(버리지 않는다, P9). */
    const val ULTRA_DISPLAY_FRESHNESS_SECONDS: Double = 120.0
    /** 흡수 세션 소비에 요구하는 이 기기 입력 창(초) — 서버 600 보다 **넓다**(P5). */
    const val ADOPTED_CONSUMER_INPUT_WINDOW_SECONDS: Double = 900.0
    /** 말풍선 큐 상한(P13). */
    const val MESSAGE_QUEUE_LIMIT: Int = 20
    /** 말풍선 전달 창(초) = 5분. 이력의 12시간과 다르다. */
    const val MESSAGE_DISPLAY_FRESHNESS_SECONDS: Double = 300.0
    /** ★ P11: 폴링은 링과 **함께** 돈다(Swift pollingKeepsRunningAlongsideRealtime). 이 값이 true 인 동안 억제는 언제나 거짓. */
    const val POLLING_KEEPS_RUNNING_ALONGSIDE_REALTIME: Boolean = true

    // ---- 안내(Swift 원문 그대로 — PokeNoticeSourceContractTest 가 Swift 소스와 견준다)
    const val ULTRA_EMPTY_NOTICE: String = "울트라가 없어요 — 상점에서 루비로 살 수 있어요"
    const val TARGET_FOCUSED_NOTICE: String = "지금 집중 중이에요. 나중에 찔러 주세요"
    const val TARGET_ON_PHONE_NOTICE: String = "폰으로 근무 중이에요. 맥으로 돌아오면 찔러 주세요"
    const val NOT_WORKING_NOTICE: String = "근무 중일 때만 콕 찌를 수 있어요"
    const val TARGET_NOT_WORKING_NOTICE: String = "자리비움 상태에는 찌를 수 없어요"
    const val INVALID_NOTICE: String = "지금은 찌를 수 없어요"
    const val NETWORK_NOTICE: String = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    const val ULTRA_COOLDOWN_NOTICE: String = "방금 찌른 상대예요. 잠시 후 울트라를 쓸 수 있어요"

    /** P3: 잔량을 모르면(null) 숫자를 지어내지 않는다. */
    fun ultraSentNotice(balance: Long?): String {
        if (balance == null) return "울트라 찌르기 발사!"
        return if (balance > 0) "울트라 발사! 남은 울트라 ${balance}개" else "울트라 발사! 이제 0개예요"
    }

    /** 폴링 억제 판정의 **단일 출처**(P11). 구독 여부는 [com.yehsung.aingcheck.feature.desktop.socialapi.RealtimeSubscription] 한 곳에서 읽는다. */
    fun pollingIsPausedByRealtime(ringIsSubscribed: Boolean): Boolean =
        if (POLLING_KEEPS_RUNNING_ALONGSIDE_REALTIME) false else ringIsSubscribed

    /** 이 순간의 폴링 주기(초) — 구독 60 · 그 밖 15. 루프가 매 반복 **앞**에서 읽는다. */
    fun pollIntervalSeconds(ringIsSubscribed: Boolean): Double =
        if (ringIsSubscribed) POLL_INTERVAL_SECONDS_WHILE_SUBSCRIBED else POLL_INTERVAL_SECONDS

    /** Swift `pokeCooldownRemaining(for:now:)` — 올림 정수 초, 음수는 0. */
    fun cooldownRemaining(until: SwiftDate?, now: SwiftDate): Int {
        if (until == null) return 0
        return max(0, ceil(until.timeIntervalSince(now)).toInt())
    }

    /**
     * P9 Swift `freshReceivedPokes(rows:now:)` — message 행은 **빠진다**(메시지가 찔림 말풍선으로 둔갑하지 않게) · 나이 ≤ 3600 ·
     * 120 초 넘은 ultra 는 normal 로 강등. 순서는 행 순서.
     */
    fun freshReceivedPokes(rows: List<TakenPokeRow>, now: SwiftDate): List<ReceivedPoke> = rows.mapNotNull { row ->
        var kind = PokeKind.of(row.kind)
        if (kind == PokeKind.message) return@mapNotNull null
        val createdAt = SwiftDate(row.createdEpoch.toDouble())
        val age = now.timeIntervalSince(createdAt)
        if (age > POKE_DISPLAY_FRESHNESS_SECONDS) return@mapNotNull null
        if (kind == PokeKind.ultra && age > ULTRA_DISPLAY_FRESHNESS_SECONDS) kind = PokeKind.normal
        ReceivedPoke(id = row.id, fromName = row.fromDisplayName, createdAt = createdAt, kind = kind, fromCharacterID = row.fromCharacter)
    }

    /**
     * P13 Swift `freshReceivedMessages(rows:now:)` — message 행만 · 본문은 보낼 때와 같은 정규화([WireTextRules.sanitized]) 뒤 비면 버린다 ·
     * 길이는 재검사하지 않는다 · 나이 ≤ 300 · createdAt 오름차순(서버 순서를 믿지 않는다, 안정 정렬).
     */
    fun freshReceivedMessages(rows: List<TakenPokeRow>, now: SwiftDate, text: WireTextRules): List<QueuedBubbleMessage> =
        rows.mapNotNull { row ->
            if (PokeKind.of(row.kind) != PokeKind.message) return@mapNotNull null
            val body = text.sanitized(row.body ?: "")
            if (body.isEmpty()) return@mapNotNull null
            val createdAt = SwiftDate(row.createdEpoch.toDouble())
            if (now.timeIntervalSince(createdAt) > MESSAGE_DISPLAY_FRESHNESS_SECONDS) return@mapNotNull null
            QueuedBubbleMessage(
                id = row.id, fromName = row.fromDisplayName, body = body, createdAt = createdAt,
                fromUserID = row.fromUser, fromAvatarURL = row.fromAvatarUrl,
            )
        }.sortedBy { it.createdAt }
}
