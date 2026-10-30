// 원본: Sources/check/WorkTimerStoreSync.swift 1669-1968(syncCurrentStatus · enqueueSync · runPendingSync ·
//       resolveStartBlockedByOpenSession · performPendingOperation) · WorkTimerStore.swift 3577-3597(큐 영속) ·
//       4469-4510(PendingWorkItem) · 3718-3725(canonical) · 76(scavengeThrottleSeconds) @ a90d8623
// 큐 항목을 만드는 쪽(syncCurrentStatus — 시작/종료/자동 마감)은 상태 갈래(W2-g5)다. 이 파일은 줄·직렬 체인·드레인·23505 해소기.
package com.yehsung.aingcheck.feature.desktop.work.queue

import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.WorkSessionRow
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.ScavengeThrottle
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import com.yehsung.aingcheck.feature.desktop.work.WorkQueueHost
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import com.yehsung.aingcheck.feature.desktop.work.service.closeAbandonedSessions
import com.yehsung.aingcheck.feature.desktop.work.service.fetchMyOverlappingSessions
import com.yehsung.aingcheck.feature.desktop.work.service.insertClosedSession
import com.yehsung.aingcheck.feature.desktop.work.service.startWork
import com.yehsung.aingcheck.feature.desktop.work.service.stopWork
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.coroutines.cancellation.CancellationException

/**
 * 오프라인 근무 큐(Swift `pendingItems` + `enqueueSync` 직렬 체인).
 *
 * 규약(work.md §2 wq):
 *  · ⑪ 순서 보존 — 한 항목이라도 실패하면 그 자리에서 멈추고 다음 주기에 재시도. 성공한 항목은 **세대 가드보다 먼저** 뺀다
 *    (세대가 올라 완료 항목이 남으면 재로그인 뒤 같은 sessionID 로 이중 재생된다 — C#23). 항목마다 ownerUserId.
 *  · ⑫ 23505 해소기: (1) 막은 행이 내 것이면 끝 → (2) 5분 스로틀 스캐빈저 뒤 한 번 재시작 → (3-a) 같은 세션 Stop 이 줄에 있으면 끝
 *    → (3-b) 지금 그 세션을 살고 있으면 [mineStart, coverageStart) 만 닫힌 행 · 도장 null → (3-c) 낡은 초안은 버림 → (3-d) 되던짐.
 *    ★ **끝 시각을 절대 고르지 않는다**(C#24). 1초 미만 구간은 쓰지 않는다. 로컬 상태는 건드리지 않는다(도장만 — 흡수는 드레인 끝 갱신).
 *  · 영속: 빈 큐는 키째 지운다(드레인 완료가 디스크에도 보이게). 깨진 데이터는 빈 큐(복원 실패로 죽지 않는다). 맥 JSON 과 바이트 호환은 요구 없음.
 */
class DesktopWorkQueue(
    private val session: SessionHost,
    private val host: WorkQueueHost,
    private val store: DesktopKeyValueStore,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
) : WorkQueue {
    companion object {
        /** 영속 키(Swift `check.workQueue.pending` 와 같은 이름 — 값 모양은 Windows 자체). */
        const val pendingWorkQueueKey = "check.workQueue.pending"
        /** Swift `scavengeThrottleSeconds`(5분) — 해소기 (2) · 팀 스캐빈저 공용 한 칸. */
        const val scavengeThrottleSeconds = 5.0 * 60.0
        const val noTeamMessage = "소속 팀이 없어요 — 팀 코드로 참여해 주세요"

        fun restore(store: DesktopKeyValueStore): List<PendingWorkItem> {
            val text = store.getString(pendingWorkQueueKey) ?: return emptyList()
            return try {
                Json.parseToJsonElement(text).jsonArray.map { decodeItem(it.jsonObject) }
            } catch (e: Exception) {
                emptyList()
            }
        }

        internal fun encodeItems(items: List<PendingWorkItem>): String = JsonArray(items.map(::encodeItem)).toString()

        private fun date(d: SwiftDate?) = d?.let { JsonPrimitive(it.timeIntervalSince1970) } ?: JsonNull
        private fun encodeItem(i: PendingWorkItem): JsonObject = JsonObject(
            linkedMapOf(
                "id" to JsonPrimitive(i.id),
                "op" to JsonPrimitive(if (i.operation is PendingWorkOperation.Stop) "stop" else "start"),
                "durationSeconds" to ((i.operation as? PendingWorkOperation.Stop)?.let { JsonPrimitive(it.durationSeconds) } ?: JsonNull),
                "sessionId" to JsonPrimitive(i.sessionId),
                "sessionStartedAt" to date(i.sessionStartedAt),
                "endedAt" to date(i.endedAt),
                "ownerUserId" to (i.ownerUserId?.let(::JsonPrimitive) ?: JsonNull),
                "autoCloseReason" to (i.autoCloseReason?.let { JsonPrimitive(it.raw) } ?: JsonNull),
            ),
        )

        private fun decodeItem(o: JsonObject): PendingWorkItem {
            fun str(k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
            fun at(k: String): SwiftDate? = (o[k] as? JsonPrimitive)?.doubleOrNull?.let { SwiftDate(it) }
            val op = when (str("op")) {
                "start" -> PendingWorkOperation.Start
                "stop" -> PendingWorkOperation.Stop(o["durationSeconds"]!!.jsonPrimitive.longOrNull!!)
                else -> error("모르는 op")
            }
            return PendingWorkItem(
                id = str("id")!!, operation = op, sessionId = str("sessionId")!!,
                sessionStartedAt = at("sessionStartedAt"), endedAt = at("endedAt"), ownerUserId = str("ownerUserId"),
                autoCloseReason = str("autoCloseReason")?.let { raw -> AutoCloseReason.entries.first { it.raw == raw } },
            )
        }
    }

    private val state = MutableStateFlow(restore(store))
    override val items: StateFlow<List<PendingWorkItem>> = state.asStateFlow()

    private val throttleLock = Any()
    private var lastScavengeAt: SwiftDate? = null
    override val scavenge: ScavengeThrottle = ScavengeThrottle { now ->
        synchronized(throttleLock) {
            val last = lastScavengeAt
            if (last != null && now.timeIntervalSince(last) < scavengeThrottleSeconds) return@ScavengeThrottle false
            lastScavengeAt = now
            true
        }
    }

    private val tailLock = Any()
    private var tail: Job? = null

    private fun mutate(transform: (List<PendingWorkItem>) -> List<PendingWorkItem>) {
        state.update(transform)
        persist(state.value)
    }

    private fun persist(list: List<PendingWorkItem>) {
        if (list.isEmpty()) store.remove(pendingWorkQueueKey) else store.putString(pendingWorkQueueKey, encodeItems(list))
    }

    /** 덧붙인다(덮어쓰지 않는다) + 직렬 체인 한 칸(Swift `pendingItems.append` + `enqueueSync`). */
    override fun enqueue(item: PendingWorkItem) {
        mutate { it + item }
        kick()
    }

    /** Swift `enqueueSync` — 앞 칸을 기다리고 → 깨움 게이트(최대 10초, 정책 갈래) → 드레인. */
    fun kick(): Job = synchronized(tailLock) {
        val previous = tail
        val job = scope.launch {
            previous?.join()
            host.awaitWakeGate()
            runPending()
        }
        tail = job
        job
    }

    /** Swift `retryPendingSync` — 줄이 있고 로그인 중일 때만 한 칸 더 걸고 끝날 때까지. */
    suspend fun retryPending() {
        if (state.value.isEmpty() || session.session == null) return
        kick().join()
    }

    /** Swift `adoptWorkStateOwner` 의 큐 몫 — 그 사용자 것이 아닌 항목(소유자 null 포함)을 걷는다. */
    override fun retainOwner(userId: String) = mutate { list -> list.filter { it.ownerUserId == userId } }

    /** finishWorkBeforeQuit: 체인 끝과 상한 중 먼저 오는 쪽. 진 쪽(체인)은 취소하지 않는다. */
    override suspend fun awaitIdle(timeoutMillis: Long) {
        val t = synchronized(tailLock) { tail } ?: return
        withTimeoutOrNull(timeoutMillis) { t.join() }
    }

    /** 해소기 왕복 중 인증 세대가 바뀌었다(Swift CancellationError) — 드레인은 세대 가드로 조용히 멈춘다. */
    private class AuthGenerationChanged : Exception("authGenerationChanged")

    private suspend fun runPending() {
        if (session.session == null || state.value.isEmpty()) return
        val generation = session.sessionGeneration
        while (true) {
            val item = state.value.firstOrNull() ?: break
            try {
                perform(item)
                // ⑪ 세대 가드보다 먼저 뺀다. 계정이 바뀌었으면 retainOwner 가 이미 걷어 first 가 달라 no-op.
                mutate { list -> if (list.firstOrNull()?.id == item.id) list.drop(1) else list }
                if (generation != session.sessionGeneration) return
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation != session.sessionGeneration) return
                host.onSyncFailed(AuthErrorRules.message(e, "동기화 실패"))
                return
            }
        }
        if (generation != session.sessionGeneration) return
        host.onDrained()
    }

    private suspend fun perform(item: PendingWorkItem) {
        val teamID = host.currentTeamId ?: throw SupabaseWorkServiceError.AuthMessage(noTeamMessage)
        when (val op = item.operation) {
            PendingWorkOperation.Start -> try {
                val inserted = session.withSessionRetry { s ->
                    session.service.startWork(s.accessToken, teamID, s.userID, item.sessionId, item.sessionStartedAt ?: clock())
                }
                // 도장 규칙 (a): 서버가 그 행을 돌려줬을 때만. null(이미 있다)은 찍지 않는다 — 열림/닫힘을 모른다.
                if (inserted != null && inserted == WorkSessionIds.canonical(item.sessionId)) host.setConfirmedServerSessionId(inserted)
            } catch (e: SupabaseWorkServiceError) {
                // ★ 23505 는 "중복"이지 "무효"가 아니다 — 버리지도, 영원히 재시도하지도 않고 해소기로.
                if (e != SupabaseWorkServiceError.SessionAlreadyOpen) throw e
                resolveStartBlockedByOpenSession(item, teamID)
            }
            is PendingWorkOperation.Stop -> session.withSessionRetry { s ->
                session.service.stopWork(
                    accessToken = s.accessToken, teamID = teamID, userID = s.userID,
                    startedAt = item.sessionStartedAt ?: clock(), endedAt = item.endedAt ?: clock(),
                    durationSeconds = op.durationSeconds, fallbackSessionID = item.sessionId, autoClosedReason = item.autoCloseReason,
                )
            }
        }
    }

    /** 정상 반환 = 이 항목은 끝났다(큐에서 뺀다). 던지기 = 순서 보존 재시도. 그 둘 말고는 없다. */
    private suspend fun resolveStartBlockedByOpenSession(item: PendingWorkItem, teamID: String) {
        val authGeneration = session.sessionGeneration
        val writeGeneration = host.workStateWriteGeneration
        val mineID = WorkSessionIds.canonical(item.sessionId)
        val mineStart = item.sessionStartedAt ?: throw SupabaseWorkServiceError.SessionAlreadyOpen
        // (1) 사실을 읽는다(오류 글자가 아니라 "내 열린 세션이 실제로 있다"를 본 뒤에만 움직인다).
        val rows: List<WorkSessionRow> = session.withSessionRetry { s ->
            session.service.fetchMyOverlappingSessions(s.accessToken, s.userID, mineStart)
        }
        if (authGeneration != session.sessionGeneration) throw AuthGenerationChanged()
        if (writeGeneration != host.workStateWriteGeneration) throw SupabaseWorkServiceError.SessionAlreadyOpen

        // Swift `try? await …` 는 String? 을 납작하게 접는다 — 성공했어도 0행(null)이면 false.
        suspend fun retryStart(): Boolean {
            val id = try {
                session.withSessionRetry { s -> session.service.startWork(s.accessToken, teamID, s.userID, item.sessionId, mineStart) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            } ?: return false
            if (id == mineID) host.setConfirmedServerSessionId(id)
            return true
        }

        val blockerID = WorkSessionIds.canonical(rows.firstOrNull { it.endedAt == null }?.id)
        if (blockerID == null) {
            // 열린 행이 안 보인다 = 오분류·그 사이 닫힘·탈퇴한 팀(RLS). 한 번만 다시 열고 아니면 되던진다.
            if (retryStart()) return
            throw SupabaseWorkServiceError.SessionAlreadyOpen
        }
        if (blockerID == mineID) {
            host.setConfirmedServerSessionId(blockerID)
            return
        }
        // (2) 슬롯을 서버 기준으로 비워 본다(마감 시각은 서버가 last_signal 로 정한다).
        if (scavenge.tryAcquire(clock())) {
            try {
                session.withSessionRetry { s -> session.service.closeAbandonedSessions(s.accessToken) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Swift `_ = try? await` — 스캐빈저 실패는 삼킨다.
            }
            if (authGeneration != session.sessionGeneration) throw AuthGenerationChanged()
            if (writeGeneration != host.workStateWriteGeneration) throw SupabaseWorkServiceError.SessionAlreadyOpen
            if (retryStart()) return
        }
        // (3-a) 같은 세션의 Stop 이 줄에 있다 → 끝은 그 항목이 들고 있다(stopWork 0행 폴백이 정본 닫힌 행을 만든다).
        if (state.value.any { it.id != item.id && WorkSessionIds.canonical(it.sessionId) == mineID && it.operation is PendingWorkOperation.Stop }) {
            return
        }
        // 핀: liveSessionId = 근무 중(startedAt != null)일 때만 canonical(currentSessionID).
        val live = host.liveSessionId
        // (3-b) 지금 그 세션을 산다 → 끝은 "아직 안 끝났다". [내 시작, 서버가 덮기 시작하는 지점)만 닫힌 행으로.
        if (live != null && live == mineID) {
            var coverageStart: SwiftDate? = null
            for (row in rows) {
                val at = SwiftISO8601.parse(row.startedAt) ?: continue
                val candidate = maxOf(at, mineStart)
                coverageStart = coverageStart?.let { minOf(it, candidate) } ?: candidate
            }
            val end = coverageStart ?: mineStart
            if (end.timeIntervalSince(mineStart) >= 1.0) {
                session.withSessionRetry { s ->
                    session.service.insertClosedSession(s.accessToken, teamID, s.userID, item.sessionId, mineStart, end)
                }
            }
            // 이 id 는 열린 행으로는 서버에 없다 — 공유 행 쓰기 금지(도장 null).
            host.setConfirmedServerSessionId(null)
            return
        }
        // (3-c) 낡은 초안(지금 다른 세션을 산다) — 버린다. 시간을 잃는 유일한 자리.
        if (live != null) return
        // (3-d) 그 밖 → 되던진다(순서 보존).
        throw SupabaseWorkServiceError.SessionAlreadyOpen
    }
}
