// 원본: Sources/CheckCore/SupabaseWorkService.swift:92-1315·1323-1592(인증·팀·프로필·미니게임·상점·메시지·제보) · SupabaseWorkServiceSignUp.swift · SupabaseWorkServiceSignUpOTP.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.text.WireScalars
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.EmptyBody
import com.yehsung.aingcheck.core.wire.MessageBody
import com.yehsung.aingcheck.core.wire.MessageBodyValidation
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.models.AvatarUpdateRequest
import com.yehsung.aingcheck.core.wire.models.BuyCharacterRequest
import com.yehsung.aingcheck.core.wire.models.BuyCharacterResponse
import com.yehsung.aingcheck.core.wire.models.CreateTeamRequest
import com.yehsung.aingcheck.core.wire.models.CreateTeamRow
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangeResponse
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangedAtRow
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackListRequest
import com.yehsung.aingcheck.core.wire.models.FeedbackReplyRequest
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackReportRow
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.FeedbackStatusRequest
import com.yehsung.aingcheck.core.wire.models.FeedbackSubmitRequest
import com.yehsung.aingcheck.core.wire.models.InviteCodeRequest
import com.yehsung.aingcheck.core.wire.models.InviteCodeRow
import com.yehsung.aingcheck.core.wire.models.JoinTeamRow
import com.yehsung.aingcheck.core.wire.models.MembershipRow
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessageHistoryRequest
import com.yehsung.aingcheck.core.wire.models.MessageHistoryRow
import com.yehsung.aingcheck.core.wire.models.MiniGameAllTimeBoardRequest
import com.yehsung.aingcheck.core.wire.models.MiniGameAllTimeBoardRow
import com.yehsung.aingcheck.core.wire.models.MiniGameAllTimeEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardRequest
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardRow
import com.yehsung.aingcheck.core.wire.models.MiniGameStartRoundRequest
import com.yehsung.aingcheck.core.wire.models.MiniGameStartRoundResponse
import com.yehsung.aingcheck.core.wire.models.MiniGameSubmitScoreRequest
import com.yehsung.aingcheck.core.wire.models.MiniGameSubmitScoreResponse
import com.yehsung.aingcheck.core.wire.models.MiniGameWinner
import com.yehsung.aingcheck.core.wire.models.MiniGameWinnerRequest
import com.yehsung.aingcheck.core.wire.models.MiniGameWinnerRow
import com.yehsung.aingcheck.core.wire.models.OpenSessionFact
import com.yehsung.aingcheck.core.wire.models.PasswordResetRequest
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
import com.yehsung.aingcheck.core.wire.models.ProfileCenterRow
import com.yehsung.aingcheck.core.wire.models.ProfileMiniGamePublicUpdateRequest
import com.yehsung.aingcheck.core.wire.models.ProfilePrivacyRow
import com.yehsung.aingcheck.core.wire.models.ProfilePrivacyUpdateRequest
import com.yehsung.aingcheck.core.wire.models.ProfileStatusMessageRow
import com.yehsung.aingcheck.core.wire.models.RefreshSessionRequest
import com.yehsung.aingcheck.core.wire.models.ResendOTPRequest
import com.yehsung.aingcheck.core.wire.models.SendMessageRequest
import com.yehsung.aingcheck.core.wire.models.SetCharacterRequest
import com.yehsung.aingcheck.core.wire.models.SetCharacterResponse
import com.yehsung.aingcheck.core.wire.models.SetDisplayNameRequest
import com.yehsung.aingcheck.core.wire.models.SetStatusMessageRequest
import com.yehsung.aingcheck.core.wire.models.SetStatusMessageResponse
import com.yehsung.aingcheck.core.wire.models.SetTeamGoalRequest
import com.yehsung.aingcheck.core.wire.models.SetTeamGoalRow
import com.yehsung.aingcheck.core.wire.models.ShopStateRequest
import com.yehsung.aingcheck.core.wire.models.ShopStateResponse
import com.yehsung.aingcheck.core.wire.models.ShopWire
import com.yehsung.aingcheck.core.wire.models.SignInRequest
import com.yehsung.aingcheck.core.wire.models.SignInResponse
import com.yehsung.aingcheck.core.wire.models.SignUpRequest
import com.yehsung.aingcheck.core.wire.models.SignUpResponse
import com.yehsung.aingcheck.core.wire.models.StatusDeviceClaim
import com.yehsung.aingcheck.core.wire.models.TeamJoinPreview
import com.yehsung.aingcheck.core.wire.models.TeamJoinPreviewRow
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardEntry
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardPage
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardRequest
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardRow
import com.yehsung.aingcheck.core.wire.models.TeamLeagueWeekClamp
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.TokenBoardRequest
import com.yehsung.aingcheck.core.wire.models.TokenBoardRow
import com.yehsung.aingcheck.core.wire.models.TokenUsageDailyRow
import com.yehsung.aingcheck.core.wire.models.UpdatePasswordRequest
import com.yehsung.aingcheck.core.wire.models.VerifyOTPRequest
import com.yehsung.aingcheck.core.wire.models.WorkSessionRow
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatusDeviceRow
import com.yehsung.aingcheck.core.wire.models.WorkStatusRow
import com.yehsung.aingcheck.core.wire.models.swiftInt
import kotlinx.coroutines.async
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.supervisorScope
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer

private val EMPTY = EmptyBody()

private fun SupabaseWorkService.empty(): ByteArray = encode(EmptyBody.serializer(), EMPTY)

// ======================================================================== 인증

suspend fun SupabaseWorkService.signIn(email: String, password: String): SupabaseSession {
    val data = send(
        "/auth/v1/token", "POST", listOf("grant_type" to "password"),
        encode(SignInRequest.serializer(), SignInRequest(email, password)), accessToken = null, prefer = null,
    )
    val r = decode(SignInResponse.serializer(), data)
    return SupabaseSession(r.accessToken, r.refreshToken, r.user.id)
}

/**
 * 계정만 만든다(팀은 가입 뒤 join_team/create_team). `center` 는 display_name 과 같은 메타 자리에 — nil 이면 키를 아예 싣지 않는다.
 * 세션이 없으면 확인 메일(null). 단 `identities: []` 면 이미 있는 계정이다(C§4 #8) → emailAlreadyRegistered.
 */
suspend fun SupabaseWorkService.signUp(email: String, password: String, displayName: String, center: String? = null): SupabaseSession? {
    val metadata = linkedMapOf("display_name" to displayName)
    if (center != null) metadata["center"] = center
    val data = send("/auth/v1/signup", "POST", emptyList(), encode(SignUpRequest.serializer(), SignUpRequest(email, password, metadata)), null, null)
    val r = decode(SignUpResponse.serializer(), data)
    val access = r.accessToken
    if (access == null) {
        val identities = r.user.identities
        if (identities != null && identities.isEmpty()) throw SupabaseWorkServiceError.EmailAlreadyRegistered
        return null
    }
    return SupabaseSession(access, r.refreshToken, r.user.id)
}

suspend fun SupabaseWorkService.refreshSession(refreshToken: String): SupabaseSession {
    val data = send(
        "/auth/v1/token", "POST", listOf("grant_type" to "refresh_token"),
        encode(RefreshSessionRequest.serializer(), RefreshSessionRequest(refreshToken)), null, null,
    )
    val r = decode(SignInResponse.serializer(), data)
    return SupabaseSession(r.accessToken, r.refreshToken, r.user.id)
}

/** 로그아웃은 `scope=local`(C§4 #6) — 다른 기기 세션을 끊지 않는다. 실패는 삼킨다. */
suspend fun SupabaseWorkService.signOut(accessToken: String) {
    swiftTryAll { send("/auth/v1/logout", "POST", listOf("scope" to "local"), null, accessToken, null) }
}

/** 폰 로그아웃 장부의 서버 정리(MobileSignOutCleanup.swift — 실패를 던진다, 장부가 재시도한다). */
suspend fun SupabaseWorkService.logoutLocalScope(accessToken: String) {
    send("/auth/v1/logout", "POST", listOf("scope" to "local"), null, accessToken, null)
}

/** INV-SupabaseWorkService-d348f33f 이식: 맥 게이트가 없다(본인 계정에만 작용) — 폰·Android 도 부른다. */
suspend fun SupabaseWorkService.deleteMyAccount(accessToken: String) {
    send("/rest/v1/rpc/delete_my_account", "POST", emptyList(), empty(), accessToken, null)
}

suspend fun SupabaseWorkService.sendPasswordResetCode(email: String) {
    try {
        send("/auth/v1/recover", "POST", emptyList(), encode(PasswordResetRequest.serializer(), PasswordResetRequest(email)), null, null)
    } catch (e: SupabaseWorkServiceError) {
        throw ServiceErrorClassifier.passwordRecoveryError(e)
    }
}

suspend fun SupabaseWorkService.verifyPasswordResetCode(email: String, code: String): SupabaseSession =
    verifyOTP(email, code, "recovery")

suspend fun SupabaseWorkService.verifySignUpCode(email: String, code: String): SupabaseSession = verifyOTP(email, code, "signup")

private suspend fun SupabaseWorkService.verifyOTP(email: String, code: String, type: String): SupabaseSession {
    try {
        val data = send("/auth/v1/verify", "POST", emptyList(), encode(VerifyOTPRequest.serializer(), VerifyOTPRequest(email, code, type)), null, null)
        val r = decode(SignInResponse.serializer(), data)
        return SupabaseSession(r.accessToken, r.refreshToken, r.user.id)
    } catch (e: SupabaseWorkServiceError) {
        throw ServiceErrorClassifier.passwordRecoveryError(e)
    }
}

suspend fun SupabaseWorkService.resendSignUpCode(email: String) {
    try {
        send("/auth/v1/resend", "POST", emptyList(), encode(ResendOTPRequest.serializer(), ResendOTPRequest("signup", email)), null, null)
    } catch (e: SupabaseWorkServiceError) {
        throw ServiceErrorClassifier.passwordRecoveryError(e)
    }
}

suspend fun SupabaseWorkService.updatePassword(accessToken: String, newPassword: String) {
    try {
        send("/auth/v1/user", "PUT", emptyList(), encode(UpdatePasswordRequest.serializer(), UpdatePasswordRequest(newPassword)), accessToken, null)
    } catch (e: SupabaseWorkServiceError) {
        throw ServiceErrorClassifier.passwordRecoveryError(e)
    }
}

// ======================================================================== 팀

/**
 * 초대 코드 정규화: 대문자, 공백·하이픈 제거(Swift `code.uppercased().filter { !$0.isWhitespace && $0 != "-" }`).
 * 공백 판정은 Swift 가 낸 번들 표([WireScalars.isWhitespace] — `Char.isWhitespace` 는 getType 이라 JDK·ART 판마다 갈린다, G §8-20 #3).
 */
fun normalizeInviteCode(code: String): String =
    WireScalars.filterScalars(code.uppercase()) { cp -> !WireScalars.isWhitespace(cp) && cp != '-'.code }

suspend fun SupabaseWorkService.lookupTeamByCode(code: String): TeamJoinPreview? {
    val data = send("/rest/v1/rpc/lookup_team_by_code", "POST", emptyList(), encode(InviteCodeRequest.serializer(), InviteCodeRequest(normalizeInviteCode(code))), null, null)
    val row = decode(ListSerializer(TeamJoinPreviewRow.serializer()), data).firstOrNull() ?: return null
    return TeamJoinPreview(row.teamId, row.name, row.weeklyGoalHours, row.memberCount)
}

suspend fun SupabaseWorkService.fetchMyInviteCode(accessToken: String): String? {
    val data = send("/rest/v1/rpc/my_team_invite_code", "POST", emptyList(), empty(), accessToken, null)
    return decode(ListSerializer(InviteCodeRow.serializer()), data).firstOrNull()?.inviteCode
}

suspend fun SupabaseWorkService.setTeamWeeklyGoal(accessToken: String, goalHours: Long): Long {
    val data = send("/rest/v1/rpc/set_team_weekly_goal", "POST", emptyList(), encode(SetTeamGoalRequest.serializer(), SetTeamGoalRequest(goalHours)), accessToken, null)
    val row = decode(ListSerializer(SetTeamGoalRow.serializer()), data).firstOrNull() ?: throw SupabaseWorkServiceError.InvalidResponse(200)
    return row.weeklyGoalHours
}

/** 팀 합류 결과(teamID, name, goalHours). */
data class JoinedTeam(val teamID: String, val name: String, val goalHours: Long)

suspend fun SupabaseWorkService.joinTeam(accessToken: String, code: String): JoinedTeam? {
    val data = send("/rest/v1/rpc/join_team", "POST", emptyList(), encode(InviteCodeRequest.serializer(), InviteCodeRequest(normalizeInviteCode(code))), accessToken, null)
    val row = decode(ListSerializer(JoinTeamRow.serializer()), data).firstOrNull() ?: return null
    return JoinedTeam(row.teamId, row.name, row.weeklyGoalHours)
}

data class CreatedTeam(val teamID: String, val name: String, val inviteCode: String, val goalHours: Long)

suspend fun SupabaseWorkService.createTeam(accessToken: String, name: String, goalHours: Long): CreatedTeam {
    val data = send("/rest/v1/rpc/create_team", "POST", emptyList(), encode(CreateTeamRequest.serializer(), CreateTeamRequest(name, goalHours)), accessToken, null)
    val row = decode(ListSerializer(CreateTeamRow.serializer()), data).firstOrNull() ?: throw SupabaseWorkServiceError.InvalidResponse(200)
    return CreatedTeam(row.teamId, row.name, row.inviteCode, row.weeklyGoalHours)
}

/** 이번 주 리그(옛 서명 — 주 인자 없음 `{}`). */
suspend fun SupabaseWorkService.fetchTeamLeaderboard(accessToken: String): List<TeamLeaderboardEntry> =
    teamLeaderboardEntries(accessToken, null)

/** 주 인자 판(0~6 으로 접어 보낸다). 서버가 함수를 모르면(databaseSchemaMissing) 옛 모양으로 한 번 더, `supportsWeekOffset=false`. */
suspend fun SupabaseWorkService.fetchTeamLeaderboard(accessToken: String, weekOffset: Long): TeamLeaderboardPage {
    val clamped = TeamLeagueWeekClamp.clamp(weekOffset)
    return try {
        TeamLeaderboardPage(teamLeaderboardEntries(accessToken, clamped), clamped, supportsWeekOffset = true)
    } catch (e: SupabaseWorkServiceError.DatabaseSchemaMissing) {
        TeamLeaderboardPage(teamLeaderboardEntries(accessToken, null), clamped, supportsWeekOffset = false)
    }
}

private suspend fun SupabaseWorkService.teamLeaderboardEntries(accessToken: String, weekOffset: Long?): List<TeamLeaderboardEntry> {
    val body = if (weekOffset != null) encode(TeamLeaderboardRequest.serializer(), TeamLeaderboardRequest(weekOffset)) else empty()
    val data = send(SupabaseWorkService.teamWeeklyLeaderboardPath, "POST", emptyList(), body, accessToken, null)
    return decode(ListSerializer(TeamLeaderboardRow.serializer()), data).map {
        TeamLeaderboardEntry(
            id = it.teamId, name = it.teamName, weeklyGoalHours = it.weeklyGoalHours, totalSeconds = it.totalSeconds,
            workingCount = it.workingCount, memberCount = it.memberCount ?: 0, center = CenterLabel.display(it.center),
            weekStart = it.weekStart, participantCount = it.participantCount,
        )
    }
}

/** 내 첫 소속(가입 순 → team_id 순, 하나). */
data class OwnMembership(val teamID: String, val teamName: String, val goalHours: Long, val role: String)

suspend fun SupabaseWorkService.fetchOwnMembership(accessToken: String, userID: String): OwnMembership? {
    val data = send(
        "/rest/v1/memberships", "GET",
        listOf("select" to "team_id,role,teams(name,weekly_goal_hours)", "user_id" to "eq.$userID", "order" to "joined_at.asc,team_id.asc", "limit" to "1"),
        null, accessToken, null,
    )
    val row = decode(ListSerializer(MembershipRow.serializer()), data).firstOrNull() ?: return null
    return membership(row)
}

fun membership(row: MembershipRow): OwnMembership = OwnMembership(
    teamID = row.teamId,
    teamName = row.teams?.name ?: "팀",
    goalHours = row.teams?.weeklyGoalHours ?: TeamWeeklyGoal.defaultGoalHours,
    role = row.role ?: "member",
)

/**
 * 팀 상태: work_statuses · 열린 세션 · 이번 주 세션 · 기기 주장 넷을 **병렬로**(Swift `async let`). 기기 주장 조회의 실패만 삼킨다
 * (증거의 부재는 아무것도 증명하지 않는다 — 표가 없는 서버에서 팀 상태 전체가 죽으면 안 된다).
 */
suspend fun SupabaseWorkService.fetchTeamStatuses(accessToken: String, teamID: String, now: SwiftDate): List<TeamMemberStatus> = supervisorScope {
    // Swift `async let` 넷은 **모두 떠난다** — 하나가 먼저 실패해도 나머지 요청은 이미 나갔다. supervisorScope 라야 한 자식의 실패가
    // 아직 출발 전인 형제를 취소하지 않는다(coroutineScope 면 부하에 따라 요청 수가 갈린다 — G5 실측).
    val statusBytes = async {
        send(
            "/rest/v1/work_statuses", "GET",
            listOf(
                "select" to "user_id,status,updated_at,last_seen_at,active_session_id,profiles(display_name,avatar_url)",
                "team_id" to "eq.$teamID",
                "order" to "updated_at.desc",
            ),
            null, accessToken, null,
        )
    }
    val active = async { fetchActiveSessions(accessToken, teamID) }
    val weekly = async { fetchWeeklySessions(accessToken, teamID, now) }
    val devices = async { swiftTryAll { fetchStatusDevices(accessToken, teamID) } }
    // 넷이 다 끝날 때까지 기다린 뒤 Swift 와 같은 차례(상태 → 활성 → 주간)로 결과·오류를 꺼낸다.
    joinAll(statusBytes, active, weekly, devices)
    val rows = decode(ListSerializer(WorkStatusRow.serializer()), statusBytes.await())
    val activeRows = active.await()
    val weeklyRows = weekly.await()
    assembleTeamStatuses(rows, activeRows, weeklyRows, devices.await() ?: emptyList(), now)
}

private suspend fun SupabaseWorkService.fetchStatusDevices(accessToken: String, teamID: String): List<WorkStatusDeviceRow> {
    val data = send(
        "/rest/v1/work_status_devices", "GET",
        listOf("select" to "user_id,device_id,session_id,last_seen_at,opened_session", "team_id" to "eq.$teamID"),
        null, accessToken, null,
    )
    return decode(ListSerializer(WorkStatusDeviceRow.serializer()), data)
}

private suspend fun SupabaseWorkService.fetchActiveSessions(accessToken: String, teamID: String): List<WorkSessionRow> {
    val data = send(
        "/rest/v1/work_sessions", "GET",
        listOf("select" to "id,user_id,started_at,ended_at,duration_seconds", "team_id" to "eq.$teamID", "ended_at" to "is.null"),
        null, accessToken, null,
    )
    return decode(ListSerializer(WorkSessionRow.serializer()), data)
}

private suspend fun SupabaseWorkService.fetchWeeklySessions(accessToken: String, teamID: String, now: SwiftDate): List<WorkSessionRow> {
    val data = send(
        "/rest/v1/work_sessions", "GET",
        listOf(
            "select" to "user_id,started_at,ended_at",
            "team_id" to "eq.$teamID",
            "ended_at" to "not.is.null",
            "ended_at" to "gte.${formatDate(TeamWeeklyGoal.koreanWeekStart(now))}",
        ),
        null, accessToken, null,
    )
    return decode(ListSerializer(WorkSessionRow.serializer()), data)
}

/** 행 → TeamMemberStatus(4 GET 경로와 work_tick 경로가 같이 부르는 한 함수 — 두 벌이 되면 화면이 갈린다). */
fun SupabaseWorkService.assembleTeamStatuses(
    rows: List<WorkStatusRow>,
    active: List<WorkSessionRow>,
    weekly: List<WorkSessionRow>,
    devices: List<WorkStatusDeviceRow>,
    now: SwiftDate,
): List<TeamMemberStatus> {
    val activeByUser = active.groupBy { it.userId }
    val weeklyByUser = durations(weekly, TeamWeeklyGoal.koreanWeekStart(now), now)
    val todayByUser = durations(weekly, TeamWeeklyGoal.koreanDayStart(now), now)
    val devicesByUser = devices.groupBy { it.userId }
    return rows.map { row ->
        val activeStartedAt = activeByUser[row.userId]?.mapNotNull { parseDate(it.startedAt) }?.minOrNull()
        val openSession = activeByUser[row.userId]
            ?.mapNotNull { s ->
                val id = s.id?.lowercase() ?: return@mapNotNull null
                val at = parseDate(s.startedAt) ?: return@mapNotNull null
                OpenSessionFact(id, at)
            }
            ?.minByOrNull { it.startedAt }
        TeamMemberStatus(
            id = row.userId,
            name = row.profiles?.displayName ?: "팀원",
            status = if (row.status == "working") WorkStatus.working else WorkStatus.offWork,
            updatedAt = row.updatedAt?.let(::parseDate),
            currentSessionStartedAt = activeStartedAt,
            weeklyDurationSeconds = weeklyByUser[row.userId] ?: 0,
            todayDurationSeconds = todayByUser[row.userId] ?: 0,
            avatarURL = SwiftURL.parse(row.profiles?.avatarUrl),
            lastSeenAt = row.lastSeenAt?.let(::parseDate),
            activeSessionID = row.activeSessionId,
            deviceClaims = (devicesByUser[row.userId] ?: emptyList()).map { d ->
                StatusDeviceClaim(d.deviceId, d.sessionId, d.lastSeenAt?.let(::parseDate), d.openedSession ?: false)
            },
            openSession = openSession,
        )
    }
}

private fun SupabaseWorkService.durations(rows: List<WorkSessionRow>, windowStart: SwiftDate, now: SwiftDate): Map<String, Long> {
    val totals = LinkedHashMap<String, Long>()
    for (row in rows) {
        val started = parseDate(row.startedAt) ?: continue
        val ended = row.endedAt?.let(::parseDate) ?: continue
        val clippedStart = maxOf(started, windowStart)
        val clippedEnd = minOf(ended, now)
        val contribution = maxOf(0L, swiftInt(clippedEnd.timeIntervalSince(clippedStart)))
        if (contribution > 0) totals[row.userId] = (totals[row.userId] ?: 0) + contribution
    }
    return totals
}

// ======================================================================== 내 기록 · 토큰 · 프로필

suspend fun SupabaseWorkService.fetchMySessions(accessToken: String, userID: String, since: SwiftDate): List<WorkSessionRow> {
    val data = send(
        "/rest/v1/work_sessions", "GET",
        listOf(
            "select" to "id,user_id,started_at,ended_at,duration_seconds",
            "user_id" to "eq.$userID",
            "ended_at" to "not.is.null",
            "ended_at" to "gte.${formatDate(since)}",
            "order" to "started_at.desc",
            "limit" to "5000",
        ),
        null, accessToken, null,
    )
    return decode(ListSerializer(WorkSessionRow.serializer()), data)
}

suspend fun SupabaseWorkService.fetchMyTokenDaily(accessToken: String, userID: String, since: String): List<TokenUsageDailyRow> {
    val data = send(
        "/rest/v1/token_usage_device_daily", "GET",
        listOf(
            "select" to "day,device_id,claude_total,codex_total,codex_utc_total,codex_account",
            "user_id" to "eq.$userID",
            "day" to "gte.$since",
            "order" to "day.desc",
            "limit" to "1000",
        ),
        null, accessToken, null,
    )
    return decode(ListSerializer(TokenUsageDailyRow.serializer()), data)
}

suspend fun SupabaseWorkService.fetchTokenBoard(accessToken: String, month: String): List<TokenBoardRow> {
    val data = send("/rest/v1/rpc/token_usage_board", "POST", emptyList(), encode(TokenBoardRequest.serializer(), TokenBoardRequest(month)), accessToken, null)
    return decode(ListSerializer(TokenBoardRow.serializer()), data)
}

private fun profileQuery(userID: String, select: String) = listOf("id" to "eq.$userID", "select" to select)

suspend fun SupabaseWorkService.fetchMiniGamePublic(accessToken: String, userID: String): Boolean? {
    val data = send("/rest/v1/profiles", "GET", profileQuery(userID, "minigame_public"), null, accessToken, null)
    return decode(ListSerializer(ProfilePrivacyRow.serializer()), data).firstOrNull()?.minigamePublic
}

suspend fun SupabaseWorkService.updateMiniGamePublic(accessToken: String, userID: String, isPublic: Boolean) {
    sendNoBody(
        "/rest/v1/profiles", "PATCH", listOf("id" to "eq.$userID"),
        encode(ProfileMiniGamePublicUpdateRequest.serializer(), ProfileMiniGamePublicUpdateRequest(isPublic)), accessToken, "return=minimal",
    )
}

/** INV-SupabaseWorkService-cce8da86 이식: center 를 **쓰는** 길(PATCH)은 일부러 없다 — 읽기만. */
suspend fun SupabaseWorkService.fetchMyCenter(accessToken: String, userID: String): String? {
    val data = send("/rest/v1/profiles", "GET", profileQuery(userID, "center"), null, accessToken, null)
    return decode(ListSerializer(ProfileCenterRow.serializer()), data).firstOrNull()?.center
}

suspend fun SupabaseWorkService.fetchMyStatusMessage(accessToken: String, userID: String): String? {
    val data = send("/rest/v1/profiles", "GET", profileQuery(userID, "status_message"), null, accessToken, null)
    return text.statusMessageDisplay(decode(ListSerializer(ProfileStatusMessageRow.serializer()), data).firstOrNull()?.statusMessage)
}

/** 상태메시지 저장 결과(Swift `StatusMessageSaveOutcome` 의 와이어 몫 — 서버에 함수가 없으면 serverNotReady). */
sealed interface StatusMessageSaveResult {
    data class Response(val response: SetStatusMessageResponse) : StatusMessageSaveResult
    data object ServerNotReady : StatusMessageSaveResult
}

suspend fun SupabaseWorkService.setStatusMessage(accessToken: String, text: String?): StatusMessageSaveResult {
    val data = try {
        send("/rest/v1/rpc/set_status_message", "POST", emptyList(), encode(SetStatusMessageRequest.serializer(), SetStatusMessageRequest(text)), accessToken, null)
    } catch (e: SupabaseWorkServiceError) {
        if (ServiceErrorClassifier.isMissingFunction(e)) return StatusMessageSaveResult.ServerNotReady
        throw e
    }
    return StatusMessageSaveResult.Response(decode(SetStatusMessageResponse.serializer(), data))
}

/** Swift `(isPublic: Bool, collects: Bool, focusMode: Bool)` — 칸이 없으면 공개 · 수집 · 집중 끔. */
data class TokenUsageSettings(val isPublic: Boolean, val collects: Boolean, val focusMode: Boolean)

suspend fun SupabaseWorkService.fetchTokenUsageSettings(accessToken: String, userID: String): TokenUsageSettings {
    val data = send("/rest/v1/profiles", "GET", profileQuery(userID, "token_usage_public,token_usage_collect,focus_mode"), null, accessToken, null)
    val first = decode(ListSerializer(ProfilePrivacyRow.serializer()), data).firstOrNull()
    return TokenUsageSettings(first?.tokenUsagePublic ?: true, first?.tokenUsageCollect ?: true, first?.focusMode ?: false)
}

suspend fun SupabaseWorkService.updateTokenUsagePublic(accessToken: String, userID: String, isPublic: Boolean) {
    sendNoBody(
        "/rest/v1/profiles", "PATCH", listOf("id" to "eq.$userID"),
        encode(ProfilePrivacyUpdateRequest.serializer(), ProfilePrivacyUpdateRequest(isPublic)), accessToken, "return=minimal",
    )
}

suspend fun SupabaseWorkService.setDisplayName(accessToken: String, name: String): DisplayNameChangeResponse {
    val data = send("/rest/v1/rpc/set_display_name", "POST", emptyList(), encode(SetDisplayNameRequest.serializer(), SetDisplayNameRequest(name)), accessToken, null)
    return decode(DisplayNameChangeResponse.serializer(), data)
}

suspend fun SupabaseWorkService.fetchDisplayNameChangedAt(accessToken: String, userID: String): SwiftDate? {
    val data = send("/rest/v1/profiles", "GET", profileQuery(userID, "display_name_changed_at"), null, accessToken, null)
    return decode(ListSerializer(DisplayNameChangedAtRow.serializer()), data).firstOrNull()?.displayNameChangedAt?.let(::parseDate)
}

/** set_character — null 이면 `{"p_id": null}`(기본 캐릭터로). */
suspend fun SupabaseWorkService.setCharacter(accessToken: String, id: String?): SetCharacterResponse {
    val data = send("/rest/v1/rpc/set_character", "POST", emptyList(), encode(SetCharacterRequest.serializer(), SetCharacterRequest(id)), accessToken, null)
    return decode(SetCharacterResponse.serializer(), data)
}

// ======================================================================== 사진(Storage)

/**
 * 사진 올리기 → profiles.avatar_url 갱신. URL 꼬리 `?v=<ms>-<uuid 앞 8자>` 는 캐시 무력화(같은 경로에 덮어쓰므로).
 * 시각·uuid 는 주입받는다(요청 골든은 꼬리를 자리표시로 접어 견준다).
 */
suspend fun SupabaseWorkService.uploadAvatar(accessToken: String, userID: String, imageData: ByteArray): String {
    sendData("/storage/v1/object/avatars/$userID.jpg", "POST", emptyList(), imageData, "image/jpeg", accessToken, mapOf("x-upsert" to "true"))
    val cacheBuster = "${swiftInt(clock().timeIntervalSince1970 * 1000)}-${newUUIDStringPrefix8()}"
    val avatarURL = "$projectURL/storage/v1/object/public/avatars/$userID.jpg?v=$cacheBuster"
    sendNoBody("/rest/v1/profiles", "PATCH", listOf("id" to "eq.$userID"), encode(AvatarUpdateRequest.serializer(), AvatarUpdateRequest(avatarURL)), accessToken, "return=minimal")
    return avatarURL
}

/** 사진 파일 지우기 결과. */
enum class AvatarFileDeletion { gone, left }

/** 사진 지우기 결과(표는 비웠는데 파일이 남았을 수 있다). */
enum class AvatarRemovalOutcome { removed, tableClearedFileLeft }

suspend fun SupabaseWorkService.removeAvatar(accessToken: String, userID: String): AvatarRemovalOutcome {
    val file = deleteAvatarFile(accessToken, userID)
    sendNoBody("/rest/v1/profiles", "PATCH", listOf("id" to "eq.$userID"), encode(AvatarUpdateRequest.serializer(), AvatarUpdateRequest(null)), accessToken, "return=minimal")
    return if (file == AvatarFileDeletion.gone) AvatarRemovalOutcome.removed else AvatarRemovalOutcome.tableClearedFileLeft
}

/** Storage DELETE(본문 없음). 2xx·404·본문의 not_found 는 '없다'(gone), 그 밖·전송 실패는 left. */
suspend fun SupabaseWorkService.deleteAvatarFile(accessToken: String, userID: String): AvatarFileDeletion {
    if (anonKey == null) return AvatarFileDeletion.left
    val r = try {
        rawRequest("/storage/v1/object/avatars/$userID.jpg", "DELETE", emptyList(), null, "application/json", accessToken, null, emptyMap())
    } catch (e: kotlin.coroutines.cancellation.CancellationException) {
        throw e
    } catch (e: Exception) {
        return AvatarFileDeletion.left
    }
    if (r.statusCode in 200..299) return AvatarFileDeletion.gone
    val body = r.body.decodeToString()
    if (r.statusCode == 404) return AvatarFileDeletion.gone
    if (body.contains("\"error\":\"not_found\"") || body.contains("\"statusCode\":\"404\"")) return AvatarFileDeletion.gone
    return AvatarFileDeletion.left
}

suspend fun SupabaseWorkService.deleteAvatarIfAny(accessToken: String, userID: String) {
    deleteAvatarFile(accessToken, userID)
}

// ======================================================================== 미니게임(게임 이름은 원시값 — MiniGameKind 는 W1-a rules)

suspend fun SupabaseWorkService.startMiniGameRound(accessToken: String, game: String): MiniGameStartRoundResponse {
    val data = send("/rest/v1/rpc/minigame_start_round", "POST", emptyList(), encode(MiniGameStartRoundRequest.serializer(), MiniGameStartRoundRequest(game)), accessToken, null)
    return decode(MiniGameStartRoundResponse.serializer(), data)
}

suspend fun SupabaseWorkService.submitMiniGameScore(accessToken: String, game: String, score: Long, token: String): MiniGameSubmitScoreResponse {
    val data = send(
        "/rest/v1/rpc/minigame_submit_score", "POST", emptyList(),
        encode(MiniGameSubmitScoreRequest.serializer(), MiniGameSubmitScoreRequest(game, score, token)), accessToken, null,
    )
    return decode(MiniGameSubmitScoreResponse.serializer(), data)
}

suspend fun SupabaseWorkService.fetchMiniGameBoard(accessToken: String, game: String, day: String? = null): List<MiniGameBoardEntry> {
    val data = send("/rest/v1/rpc/minigame_board", "POST", emptyList(), encode(MiniGameBoardRequest.serializer(), MiniGameBoardRequest(game, day)), accessToken, null)
    return decode(ListSerializer(MiniGameBoardRow.serializer()), data).map { r ->
        MiniGameBoardEntry(
            userID = r.userId, name = r.displayName ?: "사용자", avatarURL = SwiftURL.parse(r.avatarUrl), bestScore = r.bestScore,
            bestAt = r.bestAt?.let(::parseDate), plays = r.plays ?: 0, center = CenterLabel.display(r.center),
        )
    }
}

suspend fun SupabaseWorkService.fetchMiniGameYesterdayWinner(accessToken: String, game: String): MiniGameWinner? {
    val data = send("/rest/v1/rpc/minigame_yesterday_winner", "POST", emptyList(), encode(MiniGameWinnerRequest.serializer(), MiniGameWinnerRequest(game)), accessToken, null)
    val r = decode(ListSerializer(MiniGameWinnerRow.serializer()), data).firstOrNull() ?: return null
    return MiniGameWinner(
        day = r.day ?: "", userID = r.userId, name = r.displayName ?: "사용자", avatarURL = SwiftURL.parse(r.avatarUrl),
        score = r.score, awarded = r.awarded ?: false, center = CenterLabel.display(r.center),
    )
}

/**
 * 역대 순위(v0.3.67 `minigame_alltime_board`). 행 하나를 못 읽으면 **그 행만** 버린다(user_id·best_score 없는 행 — 행 디코드는
 * 어느 칸도 행을 죽이지 않는다). 정렬은 [com.yehsung.aingcheck.core.wire.models.sortedForMiniGameAllTimeBoard].
 */
suspend fun SupabaseWorkService.fetchMiniGameAllTimeBoard(accessToken: String, game: String): List<MiniGameAllTimeEntry> {
    val data = send(
        SupabaseWorkService.miniGameAllTimeBoardPath, "POST", emptyList(),
        encode(MiniGameAllTimeBoardRequest.serializer(), MiniGameAllTimeBoardRequest(game)), accessToken, null,
    )
    return decode(ListSerializer(MiniGameAllTimeBoardRow.serializer()), data).mapNotNull { r ->
        val userID = r.userId ?: return@mapNotNull null
        val score = r.bestScore ?: return@mapNotNull null
        MiniGameAllTimeEntry(
            userID = userID, name = r.displayName ?: "사용자", avatarURL = SwiftURL.parse(r.avatarUrl), bestScore = score,
            bestAt = r.bestAt?.let(::parseDate), day = r.day, center = CenterLabel.display(r.center),
        )
    }
}

// ======================================================================== 상점(C§4 #9 — 0 이면 키 생략, 404 면 5분 동안 옛 모양)

suspend fun SupabaseWorkService.fetchShopState(accessToken: String, protocolVersion: Long = ShopWire.legacyProtocol): ShopStateResponse {
    val data = sendShopRPC("/rest/v1/rpc/shop_state", protocolVersion, accessToken) { p ->
        encode(ShopStateRequest.serializer(), ShopStateRequest(p))
    }
    return decode(ShopStateResponse.serializer(), data)
}

suspend fun SupabaseWorkService.buyCharacter(accessToken: String, id: String, protocolVersion: Long = ShopWire.legacyProtocol): BuyCharacterResponse {
    val data = sendShopRPC("/rest/v1/rpc/buy_character", protocolVersion, accessToken) { p ->
        encode(BuyCharacterRequest.serializer(), BuyCharacterRequest(id, p))
    }
    return decode(BuyCharacterResponse.serializer(), data)
}

private suspend fun SupabaseWorkService.sendShopRPC(
    path: String,
    protocolVersion: Long,
    accessToken: String,
    makeBody: (Long?) -> ByteArray,
): ByteArray {
    suspend fun sendLegacy() = send(path, "POST", emptyList(), makeBody(null), accessToken, null)
    if (protocolVersion <= ShopWire.legacyProtocol || shopProtocolUnsupportedNow()) return sendLegacy()
    return try {
        send(path, "POST", emptyList(), makeBody(protocolVersion), accessToken, null)
    } catch (e: SupabaseWorkServiceError) {
        if (!ServiceErrorClassifier.isMissingFunction(e)) throw e
        val data = sendLegacy()
        // INV-SupabaseWorkService-50250b14 이식: 깃발은 **여기서만**, 두 조건이 다 맞을 때만 선다 — 새 모양이 함수 없음(PGRST202 =
        // databaseSchemaMissing)이었고 옛 모양은 성공했을 때. 맨 404(라우팅)로는 세우지 않는다.
        if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) shopProtocolUnsupportedAt = clock()
        data
    }
}

/** INV-SupabaseWorkService-2e4a31ca 이식: 깃발이 섰어도 5분이 지나면 지우고 새 모양을 다시 묻는다. */
private fun SupabaseWorkService.shopProtocolUnsupportedNow(): Boolean {
    val provenAt = shopProtocolUnsupportedAt ?: return false
    if (!(clock().timeIntervalSince(provenAt) < ShopWire.shopProtocolRecheckInterval)) {
        shopProtocolUnsupportedAt = null
        return false
    }
    return true
}

// ======================================================================== 메시지

/** 보내기 전 검증(빈 글 → invalid, 길면 too_long — 서버에 보내지 않는다). 정규화한 글자를 싣는다. */
suspend fun SupabaseWorkService.sendMessage(accessToken: String, to: String, body: String): PokeSendResponse =
    when (val v = MessageBody.validate(body, text)) {
        MessageBodyValidation.Empty -> PokeSendResponse(status = "invalid")
        is MessageBodyValidation.TooLong -> PokeSendResponse(status = "too_long", maxLength = v.maxLength)
        is MessageBodyValidation.Ok -> {
            val data = send("/rest/v1/rpc/send_message", "POST", emptyList(), encode(SendMessageRequest.serializer(), SendMessageRequest(to, v.text)), accessToken, null)
            decode(PokeSendResponse.serializer(), data)
        }
    }

/** message_history(시간 1~24 · 개수 1~500 으로 접는다). 행 → 표시: 본문 정규화 · 보이는 글자 없음/상대 없음 버림 · epoch 우선. */
suspend fun SupabaseWorkService.fetchMessageHistory(accessToken: String, hours: Long = 12, limit: Long = 200): List<MessageHistoryEntry> {
    val data = send(
        "/rest/v1/rpc/message_history", "POST", emptyList(),
        encode(MessageHistoryRequest.serializer(), MessageHistoryRequest(minOf(24L, maxOf(1L, hours)), minOf(500L, maxOf(1L, limit)))),
        accessToken, null,
    )
    return decode(ListSerializer(MessageHistoryRow.serializer()), data).mapNotNull { r ->
        val body = text.sanitized(r.body ?: "")
        if (!text.hasVisibleContent(body)) return@mapNotNull null
        val peer = r.peerUserId
        if (peer.isNullOrEmpty()) return@mapNotNull null
        val createdAt = r.createdEpoch?.let { SwiftDate(it.toDouble()) } ?: r.createdAt?.let(::parseDate) ?: return@mapNotNull null
        MessageHistoryEntry(
            id = r.id, peerUserID = peer, peerName = r.peerDisplayName?.ifEmpty { null } ?: "사용자", peerAvatarURL = SwiftURL.parse(r.peerAvatarUrl),
            body = body, createdAt = createdAt, isMine = r.isMine ?: false,
        )
    }
}

suspend fun SupabaseWorkService.fetchPokeDirectory(accessToken: String): List<PokeDirectoryRow> {
    val data = send("/rest/v1/rpc/app_user_directory", "POST", emptyList(), empty(), accessToken, null)
    return decode(ListSerializer(PokeDirectoryRow.serializer()), data)
}

// ======================================================================== 릴리스 · 공지(anon)

suspend fun SupabaseWorkService.fetchLatestRelease(): com.yehsung.aingcheck.core.wire.models.AppLatestRelease {
    val data = send("/rest/v1/rpc/app_latest_release", "POST", emptyList(), empty(), null, null)
    return decode(com.yehsung.aingcheck.core.wire.models.AppLatestRelease.serializer(), data)
}

/** 공지: 서비스 오류면 null(공지가 없는 것과 같다), 디코드 실패도 null. */
suspend fun SupabaseWorkService.appCurrentNotice(): com.yehsung.aingcheck.core.wire.models.AppNotice? {
    val data = try {
        send("/rest/v1/rpc/app_current_notice", "POST", emptyList(), empty(), null, null)
    } catch (e: SupabaseWorkServiceError) {
        return null
    }
    return swiftTry { decode(com.yehsung.aingcheck.core.wire.models.AppNotice.serializer(), data) }
}

/**
 * 플랫폼별 공지(`app_current_notice_for(p_platform)` — 마이그레이션 20261101120000). 응답 모양과 null 규칙은 [appCurrentNotice] 와 같다:
 * 서비스 오류(비2xx)면 null, 디코드 실패(공지 없음 = `{}` 포함)도 null, 전송 오류만 던진다.
 * Swift 에는 없는 함수다(맥은 [appCurrentNotice] = 'mac' 만 부른다) — Windows·Android 가 부른다. 요청 모양은 Kotlin 시험이 잠근다.
 */
suspend fun SupabaseWorkService.appCurrentNoticeFor(platform: String): com.yehsung.aingcheck.core.wire.models.AppNotice? {
    val body = kotlinx.serialization.json.JsonObject(mapOf("p_platform" to kotlinx.serialization.json.JsonPrimitive(platform)))
    val data = try {
        send("/rest/v1/rpc/app_current_notice_for", "POST", emptyList(), encode(body), null, null)
    } catch (e: SupabaseWorkServiceError) {
        return null
    }
    return swiftTry { decode(com.yehsung.aingcheck.core.wire.models.AppNotice.serializer(), data) }
}

// ======================================================================== 제보(INV-SupabaseWorkService-35ad0a8f 이식: 본문은 사용자가 쓴 글 — 로그 금지)

suspend fun SupabaseWorkService.submitFeedback(accessToken: String, kind: FeedbackKind, body: String, appVersion: String, osVersion: String): String? {
    val data = send(
        "/rest/v1/rpc/submit_feedback", "POST", emptyList(),
        encode(FeedbackSubmitRequest.serializer(), FeedbackSubmitRequest(kind.rawValue, body, appVersion, osVersion)), accessToken, null,
    )
    return swiftTry { decode(String.serializer(), data) }
}

suspend fun SupabaseWorkService.fetchFeedbackList(accessToken: String, status: FeedbackStatus?, limit: Long): List<FeedbackReport> {
    val data = send(
        "/rest/v1/rpc/feedback_list", "POST", emptyList(),
        encode(FeedbackListRequest.serializer(), FeedbackListRequest(status?.rawValue, limit)), accessToken, null,
    )
    return decode(ListSerializer(FeedbackReportRow.serializer()), data).map { r ->
        FeedbackReport(
            id = r.id, userID = r.userId, kind = FeedbackKind.of(r.kind) ?: FeedbackKind.request, body = r.body,
            status = FeedbackStatus.of(r.status ?: FeedbackStatus.Open.rawValue), adminNote = r.adminNote,
            adminNoteAt = r.adminNoteAt?.let(::parseDate), appVersion = r.appVersion, osVersion = r.osVersion,
            createdAt = r.createdAt?.let(::parseDate), updatedAt = r.updatedAt?.let(::parseDate),
            authorName = r.displayName ?: "사용자", authorAvatarURL = SwiftURL.parse(r.avatarUrl),
        )
    }
}

/** INV-SupabaseWorkService-f7a44e64 이식: 상태 바꾸기(답장과 별개의 왕복 — 답장은 [replyFeedback]). */
suspend fun SupabaseWorkService.setFeedbackStatus(accessToken: String, id: String, status: FeedbackStatus, note: String?) {
    sendNoBody(
        "/rest/v1/rpc/set_feedback_status", "POST", emptyList(),
        encode(FeedbackStatusRequest.serializer(), FeedbackStatusRequest(id, status.rawValue, note)), accessToken, null,
    )
}

/** 답장 — 응답 시각을 못 읽으면 지금. */
suspend fun SupabaseWorkService.replyFeedback(accessToken: String, id: String, note: String): SwiftDate {
    val data = send("/rest/v1/rpc/reply_feedback", "POST", emptyList(), encode(FeedbackReplyRequest.serializer(), FeedbackReplyRequest(id, note)), accessToken, null)
    return swiftTry { decode(String.serializer(), data) }?.let(::parseDate) ?: clock()
}

suspend fun SupabaseWorkService.fetchFeedbackReplyLatest(accessToken: String): SwiftDate? {
    val data = send("/rest/v1/rpc/feedback_reply_latest", "POST", emptyList(), empty(), accessToken, null)
    return swiftTry { decode(String.serializer(), data) }?.let(::parseDate)
}

suspend fun SupabaseWorkService.fetchFeedbackOpenCount(accessToken: String): Long {
    val data = send("/rest/v1/rpc/feedback_open_count", "POST", emptyList(), empty(), accessToken, null)
    return swiftTry { decode(Long.serializer(), data) } ?: 0
}
