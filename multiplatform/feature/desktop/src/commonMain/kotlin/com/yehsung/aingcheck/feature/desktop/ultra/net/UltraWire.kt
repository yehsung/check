// 원본: Sources/CheckCore/SupabaseWorkModels.swift 1730-1760(BuyUltra*·UltraWalletSyncRequest) · 1956-2185(UltraWalletResponse·MissionRow)
//       · 2185-2330(MissionProgress) @ a90d8623
// 데스크톱 전용 지갑·구매 전선 모델(W2-g4). 폰은 지갑을 부르지 않는다 — 그래서 core/wire 가 아니라 갈래 안에 둔다(poke.md §3).
package com.yehsung.aingcheck.feature.desktop.ultra.net

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encoding.Decoder

/**
 * ultra_wallet_sync 본문 `{ "p_days_back": n }`. **본문을 비우지 않는다** — PostgREST 는 본문 키 집합으로 오버로드를 고른다.
 */
@Serializable
data class UltraWalletSyncRequest(@SerialName("p_days_back") val pDaysBack: Int)

/** buy_ultra 본문 `{ "p_count": n }`. */
@Serializable
data class BuyUltraRequest(@SerialName("p_count") val pCount: Int)

/**
 * buy_ultra 응답. status 만 필수이고 나머지는 Swift 합성 디코더의 `decodeIfPresent`(없음·null = null, 타입이 다르면 던진다).
 * insufficient 일 때 need·have 가 온다(캐릭터 구매와 같은 칸).
 */
@Serializable
data class BuyUltraResponse(
    @SerialName("status") val status: String,
    @SerialName("ultra_balance") val ultraBalance: Long? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("need") val need: Long? = null,
    @SerialName("have") val have: Long? = null,
    @SerialName("unit") val unit: Long? = null,
    @SerialName("count") val count: Long? = null,
    @SerialName("max") val max: Long? = null,
)

/**
 * ultra_wallet_sync 응답(Swift `UltraWalletResponse` 직접 짠 `init(from:)` 그대로).
 *
 * - ★ status 가 "ok" 가 아니면 **거기서 끝낸다**(다른 칸을 한 줄이라도 읽으면 invalid 응답이 던짐으로 바뀐다).
 * - balance·day 는 엄격(없으면 던진다 — 관대하게 읽으면 서버 결함이 '잔량 0' 이라는 거짓말이 된다). 나머지는 관대.
 * - ⚠️1 [rubyMissionGrant]·[rubyBalance] 는 Swift CodingKeys 에 **없다** → Swift 디코더는 이 둘을 읽지 않고 언제나 nil 이다.
 *   맥과 같은 화면을 내려고 여기서도 읽지 않는다(골든 `desktop-ultra/wallet-apply` 의 ruby-mission-grant-ignored 케이스가 잠근다).
 *   Swift 가 이 칸을 읽게 고치면 골든이 바뀌고 이 디코더도 같이 바꾼다.
 */
@Serializable(with = UltraWalletResponse.Serializer::class)
data class UltraWalletResponse(
    val status: String,
    val balance: Long = 0,
    /** nil = 서버가 말 안 했다. ⚠️2 2026-09-13 상한 폐지 뒤로는 int4 최대값이 온다. */
    val balanceCap: Long? = null,
    val rubyMissionGrant: Long? = null,
    val rubyBalance: Long? = null,
    /** 반드시 Optional — nil 은 "모른다" = 무제한 아님([isUnlimited] 한 곳). */
    val unlimited: Boolean? = null,
    val dailyFloor: Long? = null,
    val day: String = "",
    val floorApplied: Boolean = false,
    val missions: List<MissionRow> = emptyList(),
    val workedSecondsClosed: Long = 0,
    val workedSecondsOpen: Long = 0,
    val streakDays: Int = 0,
    val streakIncludesToday: Boolean = false,
    val measuredAt: Long = 0,
) {
    val isOK: Boolean get() = status == "ok"

    /** **null(모름)은 무제한이 아니다** — 이 한 줄이 그 해석의 유일한 자리다. */
    val isUnlimited: Boolean get() = unlimited == true

    val workedSecondsToday: Long get() = workedSecondsClosed + workedSecondsOpen

    /** `missions[]` 원소. 랩 3형제·capped·pending 은 뒤늦게 태어난 키라 관대하게 읽는다. */
    @Serializable(with = MissionRow.Serializer::class)
    data class MissionRow(
        val key: String,
        val kstDay: String,
        val targetSeconds: Long,
        val progressSeconds: Long,
        val claimed: Boolean,
        /** **이번 호출에서** 받았다 → 연출의 유일한 트리거(★U3). */
        val grantedNow: Boolean,
        val capped: Boolean = false,
        val lapsSettled: Int = 0,
        val lapsGranted: Int = 0,
        /** null 이면 progressSeconds(랩 이전 서버는 progress 칸에 그날 총합을 담았다 — 디코더 폴백과 같은 규칙). */
        val workedSeconds: Long = progressSeconds,
        val pending: Boolean = false,
    ) {
        object Serializer : SwiftDecodableSerializer<MissionRow>("UltraWalletResponse.MissionRow") {
            override fun deserialize(decoder: Decoder): MissionRow {
                val c = SwiftDecoding.keyed(decoder)
                val progress = c.long("progress_seconds")
                return MissionRow(
                    key = c.string("key"),
                    kstDay = c.string("kst_day"),
                    targetSeconds = c.long("target_seconds"),
                    progressSeconds = progress,
                    claimed = c.bool("claimed"),
                    grantedNow = c.bool("granted_now"),
                    capped = c.boolIfPresent("capped") ?: false,
                    lapsSettled = c.intIfPresent("laps_settled") ?: 0,
                    lapsGranted = c.intIfPresent("laps_granted") ?: 0,
                    workedSeconds = c.longIfPresent("worked_seconds") ?: progress,
                    pending = c.boolIfPresent("pending") ?: false,
                )
            }
        }
    }

    object Serializer : SwiftDecodableSerializer<UltraWalletResponse>("UltraWalletResponse") {
        override fun deserialize(decoder: Decoder): UltraWalletResponse {
            val c = SwiftDecoding.keyed(decoder)
            val status = c.string("status")
            // ★ 여기서 바로 끝낸다(Swift 주석 그대로).
            if (status != "ok") return UltraWalletResponse(status = status)
            return UltraWalletResponse(
                status = status,
                balance = c.long("balance"),
                day = c.string("day"),
                balanceCap = c.longIfPresent("balance_cap"),
                unlimited = c.boolIfPresent("unlimited"),
                dailyFloor = c.longIfPresent("daily_floor"),
                floorApplied = c.boolIfPresent("floor_applied") ?: false,
                missions = c.decodeIfPresent("missions", ListSerializer(MissionRow.Serializer)) ?: emptyList(),
                workedSecondsClosed = c.longIfPresent("worked_seconds_closed") ?: 0,
                workedSecondsOpen = c.longIfPresent("worked_seconds_open") ?: 0,
                streakDays = c.intIfPresent("streak_days") ?: 0,
                streakIncludesToday = c.boolIfPresent("streak_includes_today") ?: false,
                measuredAt = c.longIfPresent("measured_at") ?: 0,
            )
        }
    }
}

/** 미션 화면 한 줄(Swift `MissionProgress`). 지갑 응답에서만 만든다 — 클라가 진행을 지어내지 않는다. */
data class MissionProgress(
    val kind: Kind,
    /** null = 바 없음(텍스트만). */
    val progress: Double?,
    val claimedToday: Boolean,
    val cappedToday: Boolean,
    val detail: String,
    val lapsGrantedToday: Int = 0,
    val isPending: Boolean = false,
) {
    enum class Kind(val raw: String) { TODAY_THREE_HOURS("work3h"), DAILY_FLOOR("dailyFloor"), ARRIVAL_STREAK("arrivalStreak") }

    val id: String get() = kind.raw

    companion object {
        const val DEFAULT_TARGET_SECONDS: Long = 3L * 3_600

        /** Swift `MissionProgress.rows(from:)`. invalid 응답은 빈 목록. */
        fun rows(response: UltraWalletResponse): List<MissionProgress> {
            if (!response.isOK) return emptyList()
            val work3h = Kind.TODAY_THREE_HOURS.raw
            // 오늘 행만 본다(어제 행은 적립을 위해 있는 것이지 화면의 '오늘 미션'이 아니다).
            val today = response.missions.firstOrNull { it.key == work3h && it.kstDay == response.day }
            // 목표: 오늘 행 → 다른 날 행 → 폴백. 0 으로 두면 0/0 이 되어 바가 100% 로 튄다.
            val target = maxOf(
                1L,
                today?.targetSeconds
                    ?: response.missions.firstOrNull { it.key == work3h }?.targetSeconds
                    ?: DEFAULT_TARGET_SECONDS,
            )
            val done = today?.progressSeconds ?: response.workedSecondsToday
            val lapsGrantedToday = today?.lapsGranted ?: 0
            val remaining = maxOf(0L, target - done)
            return listOf(
                MissionProgress(
                    kind = Kind.TODAY_THREE_HOURS,
                    progress = minOf(1.0, done.toDouble() / target.toDouble()),
                    claimedToday = today?.claimed ?: false,
                    cappedToday = today?.capped ?: false,
                    detail = if (lapsGrantedToday >= 1) "오늘 ${lapsGrantedToday}개 · 다음까지 ${hoursText(remaining)}"
                    else "다음 하나까지 ${hoursText(remaining)}",
                    lapsGrantedToday = lapsGrantedToday,
                    // 대기는 오늘 행에서만 온다.
                    isPending = today?.pending ?: false,
                ),
                MissionProgress(
                    kind = Kind.DAILY_FLOOR,
                    progress = null,
                    claimedToday = response.floorApplied,
                    cappedToday = false,
                    detail = response.dailyFloor?.let { "잔량 0이면 ${it}개로" } ?: "매일 자동 충전",
                ),
                MissionProgress(
                    kind = Kind.ARRIVAL_STREAK,
                    progress = null,
                    claimedToday = response.streakIncludesToday,
                    cappedToday = false,
                    detail = "${response.streakDays}일 연속",
                ),
            )
        }

        fun hoursText(seconds: Long): String {
            val total = maxOf(0L, seconds) / 60
            val hours = total / 60
            val minutes = total % 60
            if (hours == 0L) return "${minutes}분"
            if (minutes == 0L) return "${hours}시간"
            return "${hours}시간 ${minutes}분"
        }
    }
}
