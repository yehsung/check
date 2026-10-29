// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 21-620(근무) · 953-1016(upsertStatus · withoutNewColumns) @ a90d8623
// 빼는 것: 621-807 토큰(W2-h) · 808-952 찌르기·울트라·집중 · 939 updateAppVersion(Windows 는 profiles.app_build·app_version 을 쓰지 않는다).
// H 이름은 core/net·core/wire 에 넣지 않는다(WireRequestsGoldenTest:591 이 빨개진다) — 여기 SupabaseWorkService 확장 함수로 둔다.
// 골든: contract/golden/desktop-work/requests.json(Swift Tests/CheckMobileKitTests/GoldenExport/desktop-work).
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkSessionRow
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import com.yehsung.aingcheck.feature.desktop.work.wire.AutoCloseCorrectionRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.AutoCloseReasonPatchRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.AwayOpenSession
import com.yehsung.aingcheck.feature.desktop.work.wire.AwayPolicy
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySync
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySyncResponse
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySyncUnavailable
import com.yehsung.aingcheck.feature.desktop.work.wire.CompletedSessionRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.ReopenSessionBody
import com.yehsung.aingcheck.feature.desktop.work.wire.StartSessionRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.StatusDeviceInputRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.StatusDeviceUpsertRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.StatusUpsertRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.StopSessionRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.WorkTickFailure
import com.yehsung.aingcheck.feature.desktop.work.wire.WorkTickRequest
import com.yehsung.aingcheck.feature.desktop.work.wire.WorkTickResponse
import kotlinx.serialization.builtins.ListSerializer
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max

/** 경로 상수(H). */
object DesktopWorkPaths {
    const val workSessions = "/rest/v1/work_sessions"
    const val workStatuses = "/rest/v1/work_statuses"
    const val workStatusDevices = "/rest/v1/work_status_devices"
    const val closeAbandoned = "/rest/v1/rpc/close_abandoned_work_sessions"
    const val awaySync = "/rest/v1/rpc/away_sync"
    const val workTick = "/rest/v1/rpc/work_tick"
}

private val sessionRows = ListSerializer(WorkSessionRow.serializer())

/** ⑥ C#36: 응답 디코드 실패는 빈 배열로 접는다 — 던지면 **이미 성공한 쓰기**가 큐에서 재생된다. */
private fun SupabaseWorkService.rowsOrEmpty(data: ByteArray): List<WorkSessionRow> = try {
    decode(sessionRows, data)
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    emptyList()
}

/** Swift `try?` 를 네트워크 호출에 건 자리 — 서비스 오류·전송 실패·디코드 실패 모두 null. 취소는 삼키지 않는다. */
private inline fun <T> tryAll(block: () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    null
}

/** Swift `withoutNewColumns`: 새 칸을 모르는 서버(databaseSchemaMissing · 400)면 그 칸 없이 한 번 더. */
private suspend fun withoutNewColumns(attempt: suspend () -> Unit, retry: suspend () -> Unit) {
    try {
        attempt()
    } catch (e: SupabaseWorkServiceError) {
        if (e == SupabaseWorkServiceError.DatabaseSchemaMissing || e == SupabaseWorkServiceError.InvalidResponse(400)) retry() else throw e
    }
}

/** 맥 원본이 `Date()` 로 찍는 벽시계 칸(last_seen_at · updated_at · auto_closed_at) — 여기서는 주입 시계. */
private fun SupabaseWorkService.wallStamp(): String = formatDate(clock())

/**
 * 근무 시작(C#20). **들어간 행의 id**(소문자, 못 읽으면 null)를 돌려준다.
 * ★① 0행 = "내 id 를 가진 행이 **이미 있다**"(on_conflict=id + ignore-duplicates 는 id 충돌만 삼킨다) — "남의 세션"이 아니다.
 * 부분 유니크(work_sessions_one_open_per_user) 위반은 23505 로 올라와 [SupabaseWorkServiceError.SessionAlreadyOpen] 을 던진다.
 */
suspend fun SupabaseWorkService.startWork(
    accessToken: String,
    teamID: String,
    userID: String,
    sessionID: String,
    startedAt: SwiftDate = clock(),
): String? {
    val inserted = send(
        DesktopWorkPaths.workSessions, "POST", listOf("on_conflict" to "id"),
        encode(StartSessionRequest.serializer(), StartSessionRequest(sessionID, teamID, userID, formatDate(startedAt))),
        accessToken, "resolution=ignore-duplicates,return=representation",
    )
    upsertStatus(accessToken, teamID, userID, "working", sessionID)
    return WorkSessionIds.canonical(rowsOrEmpty(inserted).firstOrNull()?.id)
}

/**
 * 근무 종료(C#21). ★② PATCH 는 `id=eq.` 필터가 필수 — 없으면 소급 잠자기 마감이 다른 기기가 연 새 세션을 덮는다.
 * 0행이면 폴백 POST(on_conflict=id · ignore-duplicates)로 내 닫힌 행을 만든다. ③ 사유가 있으면 abandoned 만 정정(두 PATCH).
 * ④ 0행이고 내 다른 열린 행이 **보이면** off_work 꼬리를 생략(조회 실패면 꼬리를 낸다). ⑤ updateSharedStatus=false 면 공유 셀 0.
 */
suspend fun SupabaseWorkService.stopWork(
    accessToken: String,
    teamID: String,
    userID: String,
    startedAt: SwiftDate,
    endedAt: SwiftDate,
    durationSeconds: Long,
    fallbackSessionID: String,
    autoClosedReason: AutoCloseReason? = null,
    updateSharedStatus: Boolean = true,
) {
    val closedStamp = wallStamp()
    suspend fun patch(includeReason: Boolean): ByteArray = send(
        DesktopWorkPaths.workSessions, "PATCH",
        listOf(
            "id" to "eq.$fallbackSessionID",
            "team_id" to "eq.$teamID",
            "user_id" to "eq.$userID",
            "ended_at" to "is.null",
        ),
        encode(
            StopSessionRequest.serializer(),
            StopSessionRequest(
                endedAt = formatDate(endedAt),
                durationSeconds = max(0L, durationSeconds),
                autoClosedAt = if (includeReason) closedStamp else null,
                autoClosedReason = if (includeReason) autoClosedReason?.raw else null,
            ),
        ),
        accessToken, "return=representation",
    )
    var patched = ByteArray(0)
    if (autoClosedReason == null) {
        patched = patch(includeReason = false)
    } else {
        withoutNewColumns({ patched = patch(includeReason = true) }, { patched = patch(includeReason = false) })
    }
    if (rowsOrEmpty(patched).isEmpty()) {
        sendNoBody(
            DesktopWorkPaths.workSessions, "POST", listOf("on_conflict" to "id"),
            encode(
                CompletedSessionRequest.serializer(),
                CompletedSessionRequest(
                    id = fallbackSessionID, teamId = teamID, userId = userID,
                    startedAt = formatDate(startedAt), endedAt = formatDate(endedAt), durationSeconds = max(0L, durationSeconds),
                    autoClosedAt = if (autoClosedReason == null) null else closedStamp, autoClosedReason = autoClosedReason?.raw,
                ),
            ),
            accessToken, "resolution=ignore-duplicates,return=minimal",
        )
        if (autoClosedReason != null) {
            tryAll { correctAutoClose(accessToken, userID, fallbackSessionID, startedAt, endedAt, autoClosedReason, closedStamp) }
        }
        if (updateSharedStatus) {
            val openIDs = tryAll { openSessionIDs(accessToken, userID) }
            if (openIDs != null && openIDs.isNotEmpty()) return
        }
    }
    if (!updateSharedStatus) return
    upsertStatus(accessToken, teamID, userID, "off_work", null)
}

/** ③ 서버가 먼저 닫아 둔 내 세션의 사유 정정 — ended_at 은 더 이르게만, **abandoned 만** 고친다. */
private suspend fun SupabaseWorkService.correctAutoClose(
    accessToken: String,
    userID: String,
    sessionID: String,
    startedAt: SwiftDate,
    endedAt: SwiftDate,
    reason: AutoCloseReason,
    closedStamp: String,
) {
    val narrowed = send(
        DesktopWorkPaths.workSessions, "PATCH",
        listOf(
            "id" to "eq.$sessionID",
            "user_id" to "eq.$userID",
            "ended_at" to "gt.${formatDate(endedAt)}",
            "auto_closed_reason" to "eq.abandoned",
        ),
        encode(
            AutoCloseCorrectionRequest.serializer(),
            AutoCloseCorrectionRequest(
                endedAt = formatDate(endedAt),
                durationSeconds = max(0L, swiftIntTrunc(endedAt.timeIntervalSince(startedAt))),
                autoClosedAt = closedStamp,
                autoClosedReason = reason.raw,
            ),
        ),
        accessToken, "return=representation",
    )
    if (rowsOrEmpty(narrowed).isNotEmpty()) return
    sendNoBody(
        DesktopWorkPaths.workSessions, "PATCH",
        listOf(
            "id" to "eq.$sessionID",
            "user_id" to "eq.$userID",
            "ended_at" to "not.is.null",
            "auto_closed_reason" to "eq.abandoned",
        ),
        encode(AutoCloseReasonPatchRequest.serializer(), AutoCloseReasonPatchRequest(closedStamp, reason.raw)),
        accessToken, "return=minimal",
    )
}

/** Swift `Int(Double)` — 0 쪽으로 자른다. */
internal fun swiftIntTrunc(seconds: Double): Long = seconds.toLong()

/** 근무중 생존신호(공유 셀). 소유 기기는 반드시 sessionID 와 함께(⑬ — 확인된 세션 id 만 싣는 것은 호출부 몫). */
suspend fun SupabaseWorkService.heartbeat(accessToken: String, teamID: String, userID: String, sessionID: String, lastInputAt: SwiftDate? = null) {
    upsertStatus(accessToken, teamID, userID, "working", sessionID, lastInputAt)
}

/** 기기별 소유 사실(work_status_devices). openedSession = 이 기기가 그 세션을 실제로 열었는가(강한 소유) — 매번 덮어쓴다. */
suspend fun SupabaseWorkService.upsertStatusDevice(
    accessToken: String,
    teamID: String,
    userID: String,
    deviceID: String,
    sessionID: String,
    openedSession: Boolean,
    lastInputAt: SwiftDate? = null,
) {
    val stamp = wallStamp()
    suspend fun post(includeInput: Boolean) {
        sendNoBody(
            DesktopWorkPaths.workStatusDevices, "POST", listOf("on_conflict" to "team_id,user_id,device_id"),
            encode(
                StatusDeviceUpsertRequest.serializer(),
                StatusDeviceUpsertRequest(
                    teamId = teamID, userId = userID, deviceId = deviceID, sessionId = sessionID, lastSeenAt = stamp, updatedAt = stamp,
                    lastInputAt = if (includeInput) lastInputAt?.let(::formatDate) else null, openedSession = openedSession,
                ),
            ),
            accessToken, "resolution=merge-duplicates,return=minimal",
        )
    }
    if (lastInputAt == null) {
        post(includeInput = false)
        return
    }
    withoutNewColumns({ post(includeInput = true) }, { post(includeInput = false) })
}

/** ⑦ 입력 시각만(키 넷) — 흡수·미확인 상태에서도 자리 비움 판정이 빠지지 않게. */
suspend fun SupabaseWorkService.reportDeviceInput(accessToken: String, teamID: String, userID: String, deviceID: String, lastInputAt: SwiftDate) {
    sendNoBody(
        DesktopWorkPaths.workStatusDevices, "POST", listOf("on_conflict" to "team_id,user_id,device_id"),
        encode(StatusDeviceInputRequest.serializer(), StatusDeviceInputRequest(teamID, userID, deviceID, formatDate(lastInputAt))),
        accessToken, "resolution=merge-duplicates,return=minimal",
    )
}

/** 서버 스캐빈저(방치 세션 마감) — 응답 정수(못 읽으면 0). */
suspend fun SupabaseWorkService.closeAbandonedSessions(accessToken: String): Int {
    val data = send(DesktopWorkPaths.closeAbandoned, "POST", emptyList(), "{}".encodeToByteArray(), accessToken, null)
    return data.decodeToString().trim().toIntOrNull() ?: 0
}

/** 자리 비움 정책·내 열린 세션(v0.2.35). 함수 없음·디코드 실패 → [AwaySyncUnavailable]. */
suspend fun SupabaseWorkService.awaySync(accessToken: String): AwaySync {
    val data = try {
        send(DesktopWorkPaths.awaySync, "POST", emptyList(), "{}".encodeToByteArray(), accessToken, null)
    } catch (e: SupabaseWorkServiceError) {
        if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) throw AwaySyncUnavailable() else throw e
    }
    val response = tryAll { decode(AwaySyncResponse.serializer(), data) } ?: throw AwaySyncUnavailable()
    return awaySyncFrom(response)
}

/** ㉒ 임계가 >0 일 때만 정책이 선다. closeEligible 이 없으면 false. */
fun SupabaseWorkService.awaySyncFrom(response: AwaySyncResponse): AwaySync {
    val threshold = response.closeThresholdSeconds
    val policy = if (threshold != null && threshold > 0) {
        AwayPolicy(threshold.toDouble(), response.serverNow?.let(::parseDate))
    } else {
        null
    }
    val payload = response.openSession
    val open = payload?.id?.let { id ->
        AwayOpenSession(
            sessionID = id,
            startedAt = payload.startedAt?.let(::parseDate),
            lastInputAt = payload.lastInputAt?.let(::parseDate),
            closeEligible = payload.closeEligible ?: false,
        )
    }
    return AwaySync(isOK = response.status == "ok", policy = policy, openSession = open)
}

/** ⑩ p_since = KST 주 시작(core/net RpcCore 의 팀 상태 조회와 같은 포매터 · TeamWeeklyGoal.koreanWeekStart). */
fun SupabaseWorkService.makeWorkTickRequest(
    teamID: String?,
    heartbeat: Boolean,
    sessionID: String?,
    deviceID: String?,
    openedSession: Boolean,
    lastInputAt: SwiftDate?,
    includeMeta: Boolean,
    now: SwiftDate,
): WorkTickRequest = WorkTickRequest(
    pTeamId = teamID,
    pHeartbeat = heartbeat,
    pSessionId = sessionID,
    pDeviceId = deviceID,
    pOpenedSession = openedSession,
    pLastInputAt = lastInputAt?.let(::formatDate),
    pSeenAt = formatDate(now),
    pSince = formatDate(TeamWeeklyGoal.koreanWeekStart(now)),
    pIncludeMeta = includeMeta,
)

/**
 * 근무 틱 통합 RPC(⑨) — 직접 보낸다(Prefer 없음 · Content-Type 언제나). 401 → SessionExpired, 404·PGRST202 → FunctionMissing,
 * 403·42501 → Forbidden, 5xx → ServerError, 그 밖 → Rejected, 디코드 실패 → Undecodable, v≠1 → ContractMismatch.
 * 전송 오류(네트워크·취소)는 그대로 전파한다(스토어가 취소를 실패로 세지 않게).
 */
suspend fun SupabaseWorkService.workTick(accessToken: String, request: WorkTickRequest): WorkTickResponse {
    val body = encode(request.json())
    val r = rawRequest(DesktopWorkPaths.workTick, "POST", emptyList(), body, "application/json", accessToken, null, emptyMap())
    val code = postgrestErrorCode(r.body)
    when {
        r.statusCode in 200..299 -> Unit
        r.statusCode == 401 -> throw SupabaseWorkServiceError.SessionExpired
        r.statusCode == 404 -> throw WorkTickFailure.FunctionMissing(code)
        r.statusCode == 403 -> throw WorkTickFailure.Forbidden(code)
        r.statusCode >= 500 -> throw WorkTickFailure.ServerError(r.statusCode)
        code == "PGRST202" -> throw WorkTickFailure.FunctionMissing(code)
        code == "42501" -> throw WorkTickFailure.Forbidden(code)
        else -> throw WorkTickFailure.Rejected(r.statusCode, code)
    }
    val decoded = tryAll { decode(WorkTickResponse.serializer(), r.body) } ?: throw WorkTickFailure.Undecodable
    if (decoded.v != 1L) throw WorkTickFailure.ContractMismatch(decoded.v)
    return decoded
}

/** 되돌리기(30분 재개 창). 사유 칸 없는 서버면 사유 리셋 없이 한 번 더. 상태 복구(working)는 그대로 낸다. 반환 = 행 id(소문자) 또는 null. */
suspend fun SupabaseWorkService.reopenSession(accessToken: String, teamID: String, userID: String, sessionID: String): String? {
    suspend fun patch(resetAutoClose: Boolean): ByteArray = send(
        DesktopWorkPaths.workSessions, "PATCH",
        listOf("team_id" to "eq.$teamID", "id" to "eq.$sessionID"),
        encode(ReopenSessionBody.json(resetAutoClose)),
        accessToken, "return=representation",
    )
    var reopened = ByteArray(0)
    withoutNewColumns({ reopened = patch(resetAutoClose = true) }, { reopened = patch(resetAutoClose = false) })
    upsertStatus(accessToken, teamID, userID, "working", sessionID)
    return WorkSessionIds.canonical(rowsOrEmpty(reopened).firstOrNull()?.id)
}

/** 내 열린 세션 id(소문자, 최대 1) — ④ 꼬리 생략 판정용. 디코드 실패는 던진다(호출부가 try? 로 접는다). */
suspend fun SupabaseWorkService.openSessionIDs(accessToken: String, userID: String): List<String> {
    val data = send(
        DesktopWorkPaths.workSessions, "GET",
        listOf("select" to "id,user_id,started_at,ended_at", "user_id" to "eq.$userID", "ended_at" to "is.null", "limit" to "1"),
        null, accessToken, null,
    )
    return decode(sessionRows, data).mapNotNull { WorkSessionIds.canonical(it.id) }
}

/** ⑧ 23505 해소기의 사실 읽기 — **팀 필터를 걸지 않는다**(탈퇴한 팀의 열린 세션도 슬롯을 막는다). */
suspend fun SupabaseWorkService.fetchMyOverlappingSessions(accessToken: String, userID: String, since: SwiftDate): List<WorkSessionRow> {
    val data = send(
        DesktopWorkPaths.workSessions, "GET",
        listOf(
            "select" to "id,user_id,started_at,ended_at,duration_seconds",
            "user_id" to "eq.$userID",
            "or" to "(ended_at.is.null,ended_at.gte.${formatDate(since)})",
            "order" to "started_at.asc",
            "limit" to "50",
        ),
        null, accessToken, null,
    )
    return decode(sessionRows, data)
}

/** 닫힌 행 하나(해소기 3-b 의 [내 시작, 서버가 덮기 시작하는 지점)) — on_conflict=id · ignore-duplicates. */
suspend fun SupabaseWorkService.insertClosedSession(
    accessToken: String,
    teamID: String,
    userID: String,
    sessionID: String,
    startedAt: SwiftDate,
    endedAt: SwiftDate,
) {
    sendNoBody(
        DesktopWorkPaths.workSessions, "POST", listOf("on_conflict" to "id"),
        encode(
            CompletedSessionRequest.serializer(),
            CompletedSessionRequest(
                id = sessionID, teamId = teamID, userId = userID, startedAt = formatDate(startedAt), endedAt = formatDate(endedAt),
                durationSeconds = max(0L, swiftIntTrunc(endedAt.timeIntervalSince(startedAt))),
            ),
        ),
        accessToken, "resolution=ignore-duplicates,return=minimal",
    )
}

/** Swift `upsertStatus`(private) — 공유 셀. 입력 칸을 모르는 서버면 그 칸 없이 한 번 더. */
private suspend fun SupabaseWorkService.upsertStatus(
    accessToken: String,
    teamID: String,
    userID: String,
    status: String,
    activeSessionID: String?,
    lastInputAt: SwiftDate? = null,
) {
    suspend fun post(includeInput: Boolean) {
        sendNoBody(
            DesktopWorkPaths.workStatuses, "POST", listOf("on_conflict" to "team_id,user_id"),
            encode(
                StatusUpsertRequest.serializer(),
                StatusUpsertRequest(
                    teamId = teamID, userId = userID, status = status, activeSessionId = activeSessionID,
                    lastSeenAt = wallStamp(), updatedAt = wallStamp(),
                    lastInputAt = if (includeInput) lastInputAt?.let(::formatDate) else null,
                ),
            ),
            accessToken, "resolution=merge-duplicates,return=minimal",
        )
    }
    if (lastInputAt == null) {
        post(includeInput = false)
        return
    }
    withoutNewColumns({ post(includeInput = true) }, { post(includeInput = false) })
}
