// 원본: Sources/CheckCore/SupabaseWorkModels.swift:1-343·1060-1416(팀·인증·세션 행) · CheckCore/CheckWorkInsights.swift:732-770(TeamLeagueWeekNavigator.clamp) @ 1b8260d
@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.time.KST
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.atStartOfDayIn
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.time.Instant

// ---------------------------------------------------------------- 팀원 상태(조립 결과 — 전선 타입이 아니다)

/** Swift `MemberPresence` — 진실은 서버 원장(하트비트 last_seen_at), 초침은 클라 파생 표시. */
sealed interface MemberPresence {
    data object ActiveWorking : MemberPresence
    data class StaleWorking(val frozenDurationSeconds: Long) : MemberPresence
    data object OffWork : MemberPresence
}

/** Swift `WorkStatus`(근무중/근무종료). */
enum class WorkStatus { working, offWork }

/** Swift `OpenSessionFact` — 서버 work_sessions 에 실재하는 열린 행 하나(id 는 소문자, 시작시각과 **같은 행**에서 온다). */
data class OpenSessionFact(val id: String, val startedAt: SwiftDate)

/** Swift `StatusDeviceClaim`(work_status_devices 한 행). 모르면 약하다 — openedSession 기본 false. */
data class StatusDeviceClaim(
    val deviceID: String,
    val sessionID: String?,
    val lastSeenAt: SwiftDate?,
    val openedSession: Boolean = false,
)

/** Swift `TeamMemberStatus`. */
data class TeamMemberStatus(
    val id: String,
    val name: String,
    val status: WorkStatus,
    val updatedAt: SwiftDate?,
    val currentSessionStartedAt: SwiftDate?,
    val weeklyDurationSeconds: Long = 0,
    val todayDurationSeconds: Long = 0,
    val avatarURL: String? = null,
    val lastSeenAt: SwiftDate? = null,
    val activeSessionID: String? = null,
    val deviceClaims: List<StatusDeviceClaim> = emptyList(),
    val openSession: OpenSessionFact? = null,
) {
    /** seen = lastSeenAt ?? updatedAt. seen 이 없으면 살아 있다고 본다. 90초(하트비트 30초의 3배)를 넘으면 동결. */
    fun presence(now: SwiftDate): MemberPresence {
        if (status != WorkStatus.working) return MemberPresence.OffWork
        val seen = lastSeenAt ?: updatedAt ?: return MemberPresence.ActiveWorking
        if (!(now.timeIntervalSince(seen) > STALE_PRESENCE_SECONDS)) return MemberPresence.ActiveWorking
        val frozen = maxOf(0L, swiftInt(seen.timeIntervalSince(currentSessionStartedAt ?: seen)))
        return MemberPresence.StaleWorking(frozen)
    }

    fun currentDurationSeconds(now: SwiftDate): Long {
        val started = currentSessionStartedAt
        if (status != WorkStatus.working || started == null) return 0
        val p = presence(now)
        if (p is MemberPresence.StaleWorking) return p.frozenDurationSeconds
        return maxOf(0L, swiftInt(now.timeIntervalSince(started)))
    }

    fun liveWeeklyDurationSeconds(now: SwiftDate): Long = weeklyDurationSeconds + currentWeeklyContributionSeconds(now)

    fun liveTodayDurationSeconds(now: SwiftDate): Long = todayDurationSeconds + currentDurationSeconds(now)

    /** 진행 세션의 이번 주 기여 — 주 시작(KST 월 0시) 이전 구간은 귀속하지 않는다. stale 이면 마지막 신호로 클램프. */
    private fun currentWeeklyContributionSeconds(now: SwiftDate): Long {
        val started = currentSessionStartedAt
        if (status != WorkStatus.working || started == null) return 0
        val clippedStart = maxOf(started, TeamWeeklyGoal.koreanWeekStart(now))
        val end = if (presence(now) is MemberPresence.StaleWorking) lastSeenAt ?: updatedAt ?: started else now
        return maxOf(0L, swiftInt(end.timeIntervalSince(clippedStart)))
    }

    fun hasMetWeeklyGoal(goalSeconds: Long, now: SwiftDate): Boolean =
        goalSeconds > 0 && liveWeeklyDurationSeconds(now) >= goalSeconds

    companion object {
        const val STALE_PRESENCE_SECONDS: Double = 90.0
    }
}

/** Swift `Int(x: Double)` — 0 쪽으로 자른다(Kotlin `toLong()` 과 같다, 유한값 전제). */
fun swiftInt(x: Double): Long = x.toLong()

/** Swift `TeamJoinPreview`(lookup_team_by_code 결과). */
data class TeamJoinPreview(val teamID: String, val name: String, val weeklyGoalHours: Long, val memberCount: Long)

/**
 * Swift `TeamLeaderboardEntry`. `isPastWeek` 는 `TeamLeagueWeekNavigator`(W1-c insights)의 키 파싱을 쓰므로 그쪽에 둔다.
 */
data class TeamLeaderboardEntry(
    val id: String,
    val name: String,
    val weeklyGoalHours: Long,
    val totalSeconds: Long,
    val workingCount: Long,
    val memberCount: Long,
    val center: String? = null,
    val weekStart: String? = null,
    val participantCount: Long? = null,
) {
    /** 1인당 평균(초). 인원 0 이면 0. 정렬·게이지·% 의 단일 기준. */
    val averageSeconds: Long get() = if (memberCount > 0) totalSeconds / memberCount else 0

    val goal: TeamWeeklyGoal get() = TeamWeeklyGoal(workedSeconds = averageSeconds, goalSeconds = weeklyGoalHours * 3600)
}

/** 리그 정렬 단일 규약: 평균 내림차순, 동률이면 이름 오름차순(Swift `localizedStandardCompare` — [Collation] 으로 받는다). */
fun List<TeamLeaderboardEntry>.sortedByAverageDescending(collation: Collation): List<TeamLeaderboardEntry> =
    sortedWith { l, r ->
        if (l.averageSeconds != r.averageSeconds) r.averageSeconds.compareTo(l.averageSeconds)
        else collation.compare(l.name, r.name)
    }

/** 총합 0 인 팀은 숨기되 내 팀은 남긴다(정렬은 위 규약). */
fun List<TeamLeaderboardEntry>.filteredForDisplay(myTeamID: String?, collation: Collation): List<TeamLeaderboardEntry> =
    filter { it.totalSeconds != 0L || it.id == myTeamID }.sortedByAverageDescending(collation)

/** 표시 목록 + 문구를 가르는 사실 둘(`myTeamMissing` 은 원본이 비었으면 false — 통신 실패를 과거 사실로 바꾸지 않는다). */
fun List<TeamLeaderboardEntry>.leagueDisplay(myTeamID: String?, collation: Collation): TeamLeagueDisplay =
    TeamLeagueDisplay(
        entries = filteredForDisplay(myTeamID, collation),
        unfilteredCount = size.toLong(),
        myTeamMissing = isNotEmpty() && myTeamID != null && none { it.id == myTeamID },
    )

/** Swift `TeamLeagueDisplay`. */
data class TeamLeagueDisplay(val entries: List<TeamLeaderboardEntry>, val unfilteredCount: Long, val myTeamMissing: Boolean)

/** Swift `TeamLeaderboardPage`. `supportsWeekOffset` 거짓 = 주 인자를 모르는 옛 서버(이번 주로 폴백). */
data class TeamLeaderboardPage(
    val entries: List<TeamLeaderboardEntry>,
    val requestedWeekOffset: Long,
    val supportsWeekOffset: Boolean,
) {
    val serverWeekStart: String? get() = entries.firstNotNullOfOrNull { it.weekStart }
}

/** Swift `TeamLeagueWeekNavigator.maxWeeksBack`·`clamp` 의 와이어 몫(주 인자는 0~6 으로 접어 보낸다). */
object TeamLeagueWeekClamp {
    const val maxWeeksBack: Long = 6
    fun clamp(offset: Long): Long = minOf(maxOf(offset, 0L), maxWeeksBack)
}

// ---------------------------------------------------------------- 주간 목표 · KST 달력

/** Swift `TeamWeeklyGoal`(KST 월요일 시작 · 기본 60시간). */
data class TeamWeeklyGoal private constructor(val workedSeconds: Long, val goalSeconds: Long) {
    val progress: Double get() = minOf(1.0, workedSeconds.toDouble() / goalSeconds.toDouble())
    val isComplete: Boolean get() = workedSeconds >= goalSeconds
    val remainingSeconds: Long get() = maxOf(0L, goalSeconds - workedSeconds)

    companion object {
        const val defaultGoalSeconds: Long = 60L * 60 * 60
        const val defaultGoalHours: Long = defaultGoalSeconds / 3600

        operator fun invoke(workedSeconds: Long, goalSeconds: Long = defaultGoalSeconds): TeamWeeklyGoal =
            TeamWeeklyGoal(maxOf(0L, workedSeconds), maxOf(1L, goalSeconds))

        /** KST 월요일 0시(Swift `kstCalendar.dateInterval(of: .weekOfYear)` · firstWeekday = 2). */
        fun koreanWeekStart(date: SwiftDate): SwiftDate {
            val day = kstDate(date)
            val monday = day.minus(DatePeriod(days = day.dayOfWeek.isoDayNumber - DayOfWeek.MONDAY.isoDayNumber))
            return SwiftDate(monday.atStartOfDayIn(KST).epochSeconds.toDouble())
        }

        /** KST 그날 0시. */
        fun koreanDayStart(date: SwiftDate): SwiftDate = SwiftDate(kstDate(date).atStartOfDayIn(KST).epochSeconds.toDouble())

        internal fun kstDate(date: SwiftDate): LocalDate {
            val seconds = kotlin.math.floor(date.timeIntervalSince1970)
            val nanos = ((date.timeIntervalSince1970 - seconds) * 1e9).toInt()
            return Instant.fromEpochSeconds(seconds.toLong(), nanos).toLocalDateTime(KST).date
        }
    }
}

private fun pad(n: Int, width: Int): String = n.toString().padStart(width, '0')

/** Swift `TokenUsageMonthKey.current` — KST 'YYYY-MM'. */
object TokenUsageMonthKey {
    fun current(now: SwiftDate): String = TeamWeeklyGoal.kstDate(now).let { "${pad(it.year, 4)}-${pad(it.month.ordinal + 1, 2)}" }
}

/** Swift `TokenUsageDayKey.current` — KST 'YYYY-MM-DD'. */
object TokenUsageDayKey {
    fun current(now: SwiftDate): String =
        TeamWeeklyGoal.kstDate(now).let { "${pad(it.year, 4)}-${pad(it.month.ordinal + 1, 2)}-${pad(it.day, 2)}" }
}

// ---------------------------------------------------------------- 인증 요청·응답

@Serializable
data class SignInRequest(
    @SerialName("email") val email: String,
    @SerialName("password") val password: String,
)

/** 가입 본문. `data` 는 사전이라 키가 snake 변환을 타지 않는다(`display_name`·`center` 를 그대로 쓴다). */
@Serializable
data class SignUpRequest(
    @SerialName("email") val email: String,
    @SerialName("password") val password: String,
    @SerialName("data") val data: Map<String, String>,
)

@Serializable
data class InviteCodeRequest(@SerialName("code") val code: String)

@Serializable
data class CreateTeamRequest(
    @SerialName("team_name") val teamName: String,
    @SerialName("goal_hours") val goalHours: Long,
)

@Serializable
data class SetTeamGoalRequest(@SerialName("goal_hours") val goalHours: Long)

@Serializable
data class PasswordResetRequest(@SerialName("email") val email: String)

@Serializable
data class VerifyOTPRequest(
    @SerialName("email") val email: String,
    @SerialName("token") val token: String,
    @SerialName("type") val type: String,
)

@Serializable
data class UpdatePasswordRequest(@SerialName("password") val password: String)

@Serializable
data class RefreshSessionRequest(@SerialName("refresh_token") val refreshToken: String)

/** Swift `ResendOTPRequest`(SupabaseWorkServiceSignUpOTP.swift). */
@Serializable
data class ResendOTPRequest(
    @SerialName("type") val type: String,
    @SerialName("email") val email: String,
)

/** Swift `SignInResponse`: Decodable. */
@Serializable
data class SignInResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String? = null,
    @SerialName("user") val user: AuthUser,
)

/** Swift `AuthUser`: Decodable. */
@Serializable
data class AuthUser(
    @SerialName("id") val id: String,
    @SerialName("identities") val identities: List<AuthUserIdentity>? = null,
)

/** Swift `AuthUserIdentity`: Decodable. */
@Serializable
data class AuthUserIdentity(
    @SerialName("id") val id: String? = null,
)

/** Swift `ProfileRow`: Decodable. */
@Serializable
data class ProfileRow(
    @SerialName("display_name") val displayName: String,
    @SerialName("email") val email: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
)

/** Swift `WorkStatusRow`: Decodable. */
@Serializable
data class WorkStatusRow(
    @SerialName("user_id") val userId: String,
    @SerialName("status") val status: String,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String? = null,
    @SerialName("active_session_id") val activeSessionId: String? = null,
    @SerialName("profiles") val profiles: ProfileRow? = null,
)

/** Swift `WorkSessionRow`: Decodable. */
@Serializable
data class WorkSessionRow(
    @SerialName("id") val id: String? = null,
    @SerialName("user_id") val userId: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("duration_seconds") val durationSeconds: Long? = null,
)

/**
 * Swift `SignUpResponse` — 세션이 없을 수 있다(확인 메일). `user` 칸이 없으면 **같은 객체**를 사용자로 읽는다(GoTrue 판마다 다르다).
 */
@Serializable(with = SignUpResponse.Serializer::class)
data class SignUpResponse(
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val user: AuthUser,
) {
    object Serializer : SwiftDecodableSerializer<SignUpResponse>("SignUpResponse") {
        override fun deserialize(decoder: Decoder): SignUpResponse {
            val c = SwiftDecoding.keyed(decoder)
            return SignUpResponse(
                accessToken = c.stringIfPresent("access_token"),
                refreshToken = c.stringIfPresent("refresh_token"),
                user = c.decodeIfPresent("user", AuthUser.serializer()) ?: c.decodeSelf(AuthUser.serializer()),
            )
        }
    }
}

@Serializable
data class TeamJoinPreviewRow(
    @SerialName("team_id") val teamId: String,
    @SerialName("name") val name: String,
    @SerialName("weekly_goal_hours") val weeklyGoalHours: Long,
    @SerialName("member_count") val memberCount: Long,
)

@Serializable
data class JoinTeamRow(
    @SerialName("team_id") val teamId: String,
    @SerialName("name") val name: String,
    @SerialName("weekly_goal_hours") val weeklyGoalHours: Long,
)

@Serializable
data class CreateTeamRow(
    @SerialName("team_id") val teamId: String,
    @SerialName("name") val name: String,
    @SerialName("invite_code") val inviteCode: String,
    @SerialName("weekly_goal_hours") val weeklyGoalHours: Long,
)

@Serializable
data class InviteCodeRow(@SerialName("invite_code") val inviteCode: String)

@Serializable
data class SetTeamGoalRow(@SerialName("weekly_goal_hours") val weeklyGoalHours: Long)

@Serializable
data class TeamLeaderboardRequest(@SerialName("p_week_offset") val pWeekOffset: Long)

/** Swift `TeamLeaderboardRow`: Decodable. */
@Serializable
data class TeamLeaderboardRow(
    @SerialName("team_id") val teamId: String,
    @SerialName("team_name") val teamName: String,
    @SerialName("weekly_goal_hours") val weeklyGoalHours: Long,
    @SerialName("total_seconds") val totalSeconds: Long,
    @SerialName("working_count") val workingCount: Long,
    @SerialName("member_count") val memberCount: Long? = null,
    @SerialName("center") val center: String? = null,
    @SerialName("week_start") val weekStart: String? = null,
    @SerialName("participant_count") val participantCount: Long? = null,
)

/** Swift `MembershipRow`: Decodable. */
@Serializable
data class MembershipRow(
    @SerialName("team_id") val teamId: String,
    @SerialName("role") val role: String? = null,
    @SerialName("teams") val teams: MembershipTeamRow? = null,
)

/** Swift `MembershipTeamRow`: Decodable. */
@Serializable
data class MembershipTeamRow(
    @SerialName("name") val name: String,
    @SerialName("weekly_goal_hours") val weeklyGoalHours: Long? = null,
)

/** Swift `WorkStatusDeviceRow`: Decodable, Equatable. */
@Serializable
data class WorkStatusDeviceRow(
    @SerialName("user_id") val userId: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("session_id") val sessionId: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String? = null,
    @SerialName("opened_session") val openedSession: Boolean? = null,
)

/** Swift `SupabaseErrorResponse`: Decodable. */
@Serializable
data class SupabaseErrorResponse(
    @SerialName("message") val message: String? = null,
    @SerialName("msg") val msg: String? = null,
    @SerialName("error") val error: String? = null,
    @SerialName("error_description") val errorDescription: String? = null,
    @SerialName("error_code") val errorCode: String? = null,
)

/**
 * Swift `AvatarUpdateRequest` — nil 이어도 **키를 싣는다**(`{"avatar_url": null}` = 사진 지우기). encodeIfPresent 가 아니다.
 */
// INV-SupabaseWorkModels-acf4f87b 이식: nil 일 때 키를 빼면 안 된다 — 직접 짠 직렬화기가 null 을 싣는다.
@Serializable(with = AvatarUpdateRequest.Serializer::class)
data class AvatarUpdateRequest(val avatarUrl: String?) {
    object Serializer : KSerializer<AvatarUpdateRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("AvatarUpdateRequest")
        override fun serialize(encoder: Encoder, value: AvatarUpdateRequest) {
            (encoder as JsonEncoder).encodeJsonElement(
                JsonObject(mapOf("avatar_url" to (value.avatarUrl?.let { JsonPrimitive(it) } ?: JsonNull))),
            )
        }
        override fun deserialize(decoder: Decoder): AvatarUpdateRequest =
            throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}
