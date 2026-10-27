// 원본: Sources/CheckCore/SupabaseWorkModels.swift:2987-3284(미니게임 순위 · 역대 순위 v0.3.67) · 3286-3480(제보 와이어) @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.minus
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

// ---------------------------------------------------------------- 미니게임 순위(오늘)

/** Swift `MiniGameStartRoundRequest`: Encodable. */
@Serializable
data class MiniGameStartRoundRequest(
    @SerialName("p_game") val pGame: String,
)

// INV-SupabaseWorkModels-539219d4 이식: 전부 Optional(배포 창·구버전에서 디코드가 통째로 죽지 않게).
/** Swift `MiniGameStartRoundResponse`: Decodable, Equatable. */
@Serializable
data class MiniGameStartRoundResponse(
    @SerialName("status") val status: String,
    @SerialName("token") val token: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("server_now") val serverNow: String? = null,
)

/** Swift `MiniGameSubmitScoreRequest`: Encodable. */
@Serializable
data class MiniGameSubmitScoreRequest(
    @SerialName("p_game") val pGame: String,
    @SerialName("p_score") val pScore: Long,
    @SerialName("p_token") val pToken: String,
)

// INV-SupabaseWorkModels-478733a4 이식: 위와 같은 이유로 전부 Optional.
// INV-SupabaseWorkModels-7305a9db 이식: needSeconds·elapsedSeconds 는 진단 전용 — 재시도 타이밍 계산에 쓰지 않는다(로그도 금지 — C§4 #28).
/** Swift `MiniGameSubmitScoreResponse`: Decodable, Equatable. */
@Serializable
data class MiniGameSubmitScoreResponse(
    @SerialName("status") val status: String,
    @SerialName("best_score") val bestScore: Long? = null,
    @SerialName("plays") val plays: Long? = null,
    @SerialName("improved") val improved: Boolean? = null,
    @SerialName("need_seconds") val needSeconds: Double? = null,
    @SerialName("elapsed_seconds") val elapsedSeconds: Double? = null,
    @SerialName("max") val max: Long? = null,
)

/** minigame_board 본문. `p_day` 가 null 이면 키째 뺀다(오늘). */
@Serializable
data class MiniGameBoardRequest(
    @SerialName("p_game") val pGame: String,
    @SerialName("p_day") val pDay: String? = null,
)

/** Swift `MiniGameWinnerRequest`: Encodable. */
@Serializable
data class MiniGameWinnerRequest(
    @SerialName("p_game") val pGame: String,
)

/** Swift `MiniGameBoardRow`: Decodable, Equatable. */
@Serializable
data class MiniGameBoardRow(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("best_score") val bestScore: Long,
    @SerialName("best_at") val bestAt: String? = null,
    @SerialName("plays") val plays: Long? = null,
    @SerialName("center") val center: String? = null,
)

/** Swift `MiniGameWinnerRow`: Decodable, Equatable. */
@Serializable
data class MiniGameWinnerRow(
    @SerialName("day") val day: String? = null,
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("score") val score: Long,
    @SerialName("awarded") val awarded: Boolean? = null,
    @SerialName("center") val center: String? = null,
)

/** Swift `MiniGameBoardEntry`(표시). */
data class MiniGameBoardEntry(
    val userID: String,
    val name: String,
    val avatarURL: String?,
    val bestScore: Long,
    val bestAt: SwiftDate?,
    val plays: Long,
    val center: String? = null,
) {
    val id: String get() = userID
}

/** Swift `MiniGameWinner`(어제 1등). */
data class MiniGameWinner(
    val day: String,
    val userID: String,
    val name: String,
    val avatarURL: String?,
    val score: Long,
    val awarded: Boolean,
    val center: String? = null,
)

/** 오늘 순위 정렬: 점수 내림 → bestAt 이른 순(nil 은 뒤) → 이름(`localizedStandardCompare` = [Collation]). */
fun List<MiniGameBoardEntry>.sortedForMiniGameBoard(collation: Collation): List<MiniGameBoardEntry> =
    sortedWith { l, r ->
        if (l.bestScore != r.bestScore) return@sortedWith r.bestScore.compareTo(l.bestScore)
        val la = l.bestAt
        val ra = r.bestAt
        when {
            la != null && ra != null && la != ra -> la.compareTo(ra)
            la == null && ra != null -> 1
            la != null && ra == null -> -1
            else -> collation.compare(l.name, r.name)
        }
    }

/** Swift `MiniGameDayKey` — KST 'YYYY-MM-DD'(어제 = KST 달력으로 하루 전). */
object MiniGameDayKey {
    fun key(date: SwiftDate): String = TokenUsageDayKey.current(date)

    fun yesterday(now: SwiftDate): String {
        val d = TeamWeeklyGoal.kstDate(now).minus(DatePeriod(days = 1))
        return "${d.year.toString().padStart(4, '0')}-${(d.month.ordinal + 1).toString().padStart(2, '0')}-${d.day.toString().padStart(2, '0')}"
    }
}

// ---------------------------------------------------------------- 역대 순위(v0.3.67)

/** Swift `MiniGameBoardScope`(오늘 · 역대). */
enum class MiniGameBoardScope(val rawValue: String) {
    today("today"), allTime("allTime");

    val id: String get() = rawValue
    val label: String get() = when (this) { today -> "오늘"; allTime -> "역대" }
    val boardTitle: String get() = when (this) { today -> "오늘 순위"; allTime -> "역대 순위" }
}

@Serializable
data class MiniGameAllTimeBoardRequest(@SerialName("p_game") val pGame: String)

/**
 * Swift `MiniGameAllTimeBoardRow`(minigame_alltime_board 행) — **어느 칸도 행 전체를 죽이지 않는다**: 칸마다 `try?`,
 * 글자 칸(user_id·avatar_url·best_at·day·center)은 앞뒤 공백을 잘라 비면 null. display_name 은 자르지 않는다.
 * 객체가 아니면 전부 null 인 행(서비스가 user_id·best_score 없는 행을 버린다).
 */
@Serializable(with = MiniGameAllTimeBoardRow.Serializer::class)
data class MiniGameAllTimeBoardRow(
    val userId: String?,
    val displayName: String?,
    val avatarUrl: String?,
    val bestScore: Long?,
    val bestAt: String?,
    val day: String?,
    val center: String?,
) {
    object Serializer : SwiftDecodableSerializer<MiniGameAllTimeBoardRow>("MiniGameAllTimeBoardRow") {
        override fun deserialize(decoder: Decoder): MiniGameAllTimeBoardRow {
            val c = swiftTry { SwiftDecoding.keyed(decoder) }
                ?: return MiniGameAllTimeBoardRow(null, null, null, null, null, null, null)
            fun text(key: String): String? {
                val value = c.lossyString(key) ?: return null
                val trimmed = swiftTrim(value)
                return trimmed.ifEmpty { null }
            }
            return MiniGameAllTimeBoardRow(
                userId = text("user_id"),
                displayName = c.lossyString("display_name"),
                avatarUrl = text("avatar_url"),
                bestScore = c.lossyLong("best_score"),
                bestAt = text("best_at"),
                day = text("day"),
                center = text("center"),
            )
        }
    }
}

/** Swift `MiniGameAllTimeEntry`(역대 순위 한 줄 — `day` 는 그 기록이 난 KST 날). */
data class MiniGameAllTimeEntry(
    val userID: String,
    val name: String,
    val avatarURL: String?,
    val bestScore: Long,
    val bestAt: SwiftDate?,
    val day: String?,
    val center: String? = null,
) {
    val id: String get() = userID
    val dayCaption: String? get() = dayCaption(day)

    /** 오늘 순위 줄 그리기를 그대로 쓰기 위한 변환(plays 0). */
    val rankRowEntry: MiniGameBoardEntry
        get() = MiniGameBoardEntry(userID = userID, name = name, avatarURL = avatarURL, bestScore = bestScore, bestAt = bestAt, plays = 0, center = center)

    companion object {
        /** 'YYYY-MM-DD' → "M/D"(앞 0 없음). 모양·범위가 어긋나면 null — ASCII 숫자만 받는다. */
        fun dayCaption(day: String?): String? {
            if (day == null) return null
            val parts = day.split('-')
            if (parts.size != 3 || parts[0].length != 4 || parts[1].length != 2 || parts[2].length != 2) return null
            if (!parts.all { p -> p.all { it in '0'..'9' } }) return null
            val month = parts[1].toIntOrNull() ?: return null
            val date = parts[2].toIntOrNull() ?: return null
            if (month !in 1..12 || date !in 1..31) return null
            return "$month/$date"
        }
    }
}

/** 역대 순위 정렬: 점수 내림 → bestAt 이른 순(nil 은 뒤) → userID(이름 정렬에 기대지 않는다). */
fun List<MiniGameAllTimeEntry>.sortedForMiniGameAllTimeBoard(): List<MiniGameAllTimeEntry> =
    sortedWith { l, r ->
        if (l.bestScore != r.bestScore) return@sortedWith r.bestScore.compareTo(l.bestScore)
        val la = l.bestAt
        val ra = r.bestAt
        when {
            la != null && ra != null && la != ra -> la.compareTo(ra)
            la == null && ra != null -> 1
            la != null && ra == null -> -1
            else -> l.userID.compareTo(r.userID)
        }
    }

// ---------------------------------------------------------------- 제보(버그·요청)

/** Swift `FeedbackKind`. */
enum class FeedbackKind(val rawValue: String) {
    bug("bug"), request("request");

    val id: String get() = rawValue
    val label: String get() = when (this) { bug -> "버그"; request -> "요청" }
    val isDanger: Boolean get() = this == bug

    companion object {
        fun of(raw: String): FeedbackKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

// INV-SupabaseWorkModels-7454ae4b 이식: 갈래 이름과 rawValue 가 일부러 다르다(inProgress = "doing", held = "wontfix").
/** Swift `FeedbackStatus`(모르는 값은 `other(raw)` — 운영자가 새 상태를 만들어도 목록이 죽지 않는다). */
sealed interface FeedbackStatus {
    data object Open : FeedbackStatus
    data object InProgress : FeedbackStatus
    data object Done : FeedbackStatus
    data object Held : FeedbackStatus
    data class Other(val raw: String) : FeedbackStatus

    val rawValue: String
        get() = when (this) { Open -> "open"; InProgress -> "doing"; Done -> "done"; Held -> "wontfix"; is Other -> raw }

    val label: String
        get() = when (this) { Open -> "미해결"; InProgress -> "진행"; Done -> "완료"; Held -> "보류"; is Other -> raw }

    val isOpen: Boolean get() = this == Open

    companion object {
        fun of(rawValue: String): FeedbackStatus = when (rawValue) {
            "open" -> Open; "doing" -> InProgress; "done" -> Done; "wontfix" -> Held; else -> Other(rawValue)
        }
        val known: List<FeedbackStatus> = listOf(Open, InProgress, Done, Held)
        val transitions: List<FeedbackStatus> = known
    }
}

@Serializable
data class FeedbackSubmitRequest(
    @SerialName("p_kind") val pKind: String,
    @SerialName("p_body") val pBody: String,
    @SerialName("p_app_version") val pAppVersion: String,
    @SerialName("p_os_version") val pOsVersion: String,
)

/** `p_status` 가 null 이면 키째 뺀다(전체). */
@Serializable
data class FeedbackListRequest(
    @SerialName("p_status") val pStatus: String? = null,
    @SerialName("p_limit") val pLimit: Long,
)

@Serializable
data class FeedbackStatusRequest(
    @SerialName("p_id") val pId: String,
    @SerialName("p_status") val pStatus: String,
    @SerialName("p_note") val pNote: String? = null,
)

@Serializable
data class FeedbackReplyRequest(
    @SerialName("p_id") val pId: String,
    @SerialName("p_note") val pNote: String,
)

/** Swift `FeedbackReportRow`: Decodable, Equatable. */
@Serializable
data class FeedbackReportRow(
    @SerialName("id") val id: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("kind") val kind: String,
    @SerialName("body") val body: String,
    @SerialName("status") val status: String? = null,
    @SerialName("admin_note") val adminNote: String? = null,
    @SerialName("admin_note_at") val adminNoteAt: String? = null,
    @SerialName("app_version") val appVersion: String? = null,
    @SerialName("os_version") val osVersion: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
)

/** Swift `FeedbackReport`(표시). */
data class FeedbackReport(
    val id: String,
    val userID: String?,
    val kind: FeedbackKind,
    val body: String,
    val status: FeedbackStatus,
    val adminNote: String?,
    val adminNoteAt: SwiftDate? = null,
    val appVersion: String?,
    val osVersion: String?,
    val createdAt: SwiftDate?,
    val updatedAt: SwiftDate?,
    val authorName: String,
    val authorAvatarURL: String?,
) {
    /** 운영자 답장(앞뒤 공백을 자르고 비면 null). */
    val reply: String? get() = adminNote?.let { swiftTrim(it) }?.ifEmpty { null }
}
