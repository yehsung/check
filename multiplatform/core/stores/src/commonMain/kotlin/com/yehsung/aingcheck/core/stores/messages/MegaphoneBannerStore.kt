// 원본: Sources/CheckCore/MegaphoneBannerStore.swift @ a6791165(b056075b) — 확성기 배너 스토어(맥·폰 한 벌 — 계약 docs/plan/megaphone-banner-contract.md C2 · C3)
//
// [MegaphoneStore] 와 같은 결: 세션 호스트([SessionHost] — 폰 조립은 PhoneMegaphoneHost)를 빌려 RPC 를 부른다.
// 화면(폰 위 배너)은 [current] 하나만 그린다. 이 파일이 지키는 것:
//
// ① **메시지함 필터의 근거는 [knownMessageIDs] 하나다.** `megaphone_inbox` 가 성공했을 때만 채운다. 숨김 술어 [hides] 는
//    `capability == available` 일 때만 참이다 — 서버에 새 함수가 없으면(unavailable) 지금처럼 메시지로 보인다(잃는 것이 없다).
// ② **본문 접두(`📢 `)는 표식이 아니다.** 접두만 있고 ID 를 모르는 줄은 [needsVerification] 이 "판정 보류"를 말하고, 부르는 쪽이
//    `refresh(verifying)` 를 한 번 기다린 뒤 다시 거른다. 그 refresh 뒤에도 모르면(위조 DM · 연결 실패) 메시지로 보인다.
// ③ **안 읽음 요약과 필터는 함께 움직인다.** 필터가 켜져 있으면 확성기 줄을 안 세는 `message_unread_summary_v2` 를, 아니면 옛 함수를
//    쓴다. v2 가 없으면(PGRST202 · 404) 옛 함수로 내리고 **필터도 끈다** — 줄만 숨기고 옛 요약이 그 줄을 세면 배지가 영영 안 꺼진다.
// ④ **한 번에 하나 · 8초 · 쉬고 0.4초.** 타이머는 주입([clock] · [schedule])이라 시험이 8초를 기다리지 않는다. 지난 타이머는
//    timerToken 으로 버린다(취소 대신 세대).
// ⑤ **본 것 기록**: 계정별 키로 최근 100개 megaphoneID 를 기본값 저장소에 — 재실행해도 같은 확성기를 두 번 안 띄운다.
//    (기기 사이에는 나누지 않는다.) [reset] 은 메모리 캐시만 비운다(기록은 계정 키에 남는다).
package com.yehsung.aingcheck.core.stores.messages

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.fetchMessageUnreadSummary
import com.yehsung.aingcheck.core.net.megaphoneInboxRaw
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.core.rules.text.MegaphoneBannerRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneInboxItem
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MessageUnreadSummaryResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 배너 타이머를 거는 곳. [after] 초 뒤 [fire] 를 부른다. 취소는 없다 — 스토어가 세대로 지난 것을 버린다. */
typealias MegaphoneBannerSchedule = (after: Double, fire: () -> Unit) -> Unit

@OptIn(ExperimentalUuidApi::class)
class MegaphoneBannerStore(
    host: SessionHost?,
    private val scope: CoroutineScope,
    /** 본 것 기록을 두는 곳(null 이면 프로세스 안에만 — 시험·미리보기). */
    private val defaults: KeyValueStore?,
    /** 시각(신선도 · 남은 표시 시간). */
    var clock: () -> SwiftDate,
    schedule: MegaphoneBannerSchedule? = null,
) {
    /** 서버가 배너 RPC 를 아는가. */
    enum class Capability {
        /** 아직 안 물어봤다(로그인 직후) — 필터 꺼짐 · 접두 줄은 판정 보류. */
        unknown,

        /** `megaphone_inbox` 가 성공했다 — 필터 켜짐 · 안 읽음 요약은 v2. */
        available,

        /** inbox 또는 v2 가 없다(옛 서버) — 필터 꺼짐 · 지금처럼 메시지로. */
        unavailable,
    }

    /** 네트워크·세션을 빌리는 곳. 소유자가 이 스토어를 쥔다. */
    var host: SessionHost? = host
        private set

    /** 타이머(8초 · 0.4초 · 멈춤 뒤 다시 세기). */
    var schedule: MegaphoneBannerSchedule = schedule ?: { after, fire ->
        this.scope.launch {
            delay((maxOf(0.0, after) * 1000).toLong())
            fire()
        }
    }

    /** 지금 배너를 미뤄야 하는가(폰: 시트·대결 화면·미니게임 판). 바뀌면 [deferralChanged] 를 부른다. */
    var isBannerDeferred: () -> Boolean = { false }

    // ---------------------------------------------------------------- 상태(화면이 읽는다)

    var capability: Capability by mutableStateOf(Capability.unknown)
        private set

    /** 메시지함에서 뺄 줄의 id — `megaphone_inbox` 가 돌려준 것만(한 세션 동안 늘기만 한다). */
    var knownMessageIDs: Set<String> by mutableStateOf(emptySet())
        private set

    /** 지금 떠 있는 배너. null = 없음. */
    var current: MegaphoneBanner? by mutableStateOf(null)
        private set

    /** 기다리는 배너(앞에서부터 뜬다). */
    var queue: List<MegaphoneBanner> by mutableStateOf(emptyList())
        private set

    /** 누르고 있기로 타이머가 멈춰 있는가. */
    var isTimerPaused: Boolean by mutableStateOf(false)
        private set

    /** v2 안 읽음 요약이 없는 서버였다(이 세션 동안 필터를 끈 채 둔다 — 머리말 ③). */
    var unreadSummaryV2Missing: Boolean by mutableStateOf(false)
        private set

    /** 마지막 refresh 가 연결 문제로 실패했다(함수 없음은 여기가 아니라 [capability]). */
    var lastRefreshFailed: Boolean by mutableStateOf(false)
        private set

    /** refresh 한 번을 지났는데도 inbox 에 없던 접두 줄(위조 DM · 연결 실패) — 더는 판정을 미루지 않는다. */
    var checkedMessageIDs: Set<String> by mutableStateOf(emptySet())
        private set

    // ---------------------------------------------------------------- 내부

    private var fromPushIDs: MutableSet<String> = LinkedHashSet()
    private var currentFromPush = false
    private var verifyQueue: Set<String> = emptySet()
    private var refreshJob: Job? = null
    private var rerunRequested = false
    private var timerToken = 0
    private var currentDeadline: SwiftDate? = null
    private var pausedRemaining = 0.0
    private var inGap = false
    private var resetGeneration = 0
    private var seenCache: Pair<String, List<String>>? = null

    /** 세션이 없을 때(이론상) 쓰는 기록 — 저장하지 않는다. */
    private var memorySeen: List<String> = emptyList()

    fun attach(host: SessionHost) {
        this.host = host
    }

    // ---------------------------------------------------------------- 메시지함 필터(C3 — 한 술어, 모든 자리)

    /** 이 줄을 메시지함·배지에서 뺄 것인가. **필터가 켜져 있고(available) inbox 가 그 id 를 말했을 때만** 참. */
    fun hides(messageID: String): Boolean = capability == Capability.available && messageID in knownMessageIDs

    /**
     * 이 줄의 판정을 미룰 것인가 — 본문이 `📢` 로 시작하는데 id 를 아직 모르고, 필터가 꺼진 서버가 아니며, refresh 를 한 번 지나지 않았다.
     * 참이면 부르는 쪽은 그 줄을 잠시 붙들고 `refresh(verifying)` 를 기다린 뒤 다시 거른다(접두만 보고 숨기지 않는다).
     */
    fun needsVerification(messageID: String, body: String): Boolean {
        if (capability == Capability.unavailable || !MegaphoneBanner.hasMegaphonePrefix(body)) return false
        return messageID !in knownMessageIDs && messageID !in checkedMessageIDs
    }

    /** 지금 쓸 안 읽음 요약 함수 이름. 필터가 켜져 있으면 v2, 아니면 옛 함수(머리말 ③). */
    val unreadSummaryFunction: String
        get() = if (capability == Capability.available && !unreadSummaryV2Missing) UNREAD_SUMMARY_V2 else UNREAD_SUMMARY_V1

    /** 요약 호출이 실패했을 때 알려 준다. v2 가 없는 서버면 필터를 끄고 **true**(옛 함수로 다시 부를 것) — 그 밖은 false. */
    fun noteUnreadSummaryFailure(function: String, error: Throwable): Boolean {
        if (function != UNREAD_SUMMARY_V2 || !isMissingFunction(error)) return false
        unreadSummaryV2Missing = true
        if (capability != Capability.unavailable) capability = Capability.unavailable
        return true
    }

    /** 안 읽음 요약을 받는다 — [unreadSummaryFunction] 으로 부르고, v2 가 없으면 필터를 끈 뒤 옛 함수로 한 번 더 부른다. */
    suspend fun fetchUnreadSummary(): MessageUnreadSummaryResponse {
        val host = host ?: throw CancellationException("배너 호스트 없음")
        val service = host.service
        val generation = resetGeneration
        val function = unreadSummaryFunction
        return try {
            host.withSessionRetry { session -> service.fetchMessageUnreadSummary(session.accessToken, function) }
        } catch (error: Throwable) {
            if (generation != resetGeneration || !noteUnreadSummaryFailure(function, error)) throw error
            host.withSessionRetry { session -> service.fetchMessageUnreadSummary(session.accessToken, UNREAD_SUMMARY_V1) }
        }
    }

    // ---------------------------------------------------------------- 받아 오기

    /**
     * `megaphone_inbox` 를 불러 [knownMessageIDs] 를 늘리고, 새로 본 신선한 항목을 줄 세운다.
     * 겹친 호출은 하나로 모이되, 진행 중에 들어온 요청은 **한 번 더** 돈다(그 사이 도착한 확성기를 놓치지 않게).
     * [verifying] 의 id 는 이 refresh 가 끝난 뒤 판정이 확정된다: inbox 에 있으면 숨김, 없으면(연결 실패 포함) 메시지.
     */
    suspend fun refresh(verifying: Set<String> = emptySet()) {
        verifyQueue = verifyQueue + verifying
        refreshJob?.let { running ->
            rerunRequested = true
            running.join()
            return
        }
        val generation = resetGeneration
        // LAZY: 즉시 디스패처에서 몸통이 먼저 끝나 [refreshJob] 에 끝난 작업이 남지 않게 — 자리를 먼저 잡고 join 이 띄운다.
        lateinit var job: Job
        job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                do {
                    rerunRequested = false
                    val batch = verifyQueue
                    verifyQueue = emptySet()
                    performRefresh()
                    if (generation != resetGeneration) return@launch
                    val unresolved = batch - knownMessageIDs
                    if (!checkedMessageIDs.containsAll(unresolved)) checkedMessageIDs = checkedMessageIDs + unresolved
                } while (rerunRequested)
            } finally {
                if (refreshJob === job) refreshJob = null
            }
        }
        refreshJob = job
        job.join()
    }

    private suspend fun performRefresh() {
        val host = host ?: return
        if (host.session == null) return
        val sessionGeneration = host.sessionGeneration
        val generation = resetGeneration
        val service = host.service
        try {
            val raw = host.withSessionRetry { session -> service.megaphoneInboxRaw(session.accessToken, MegaphoneBannerRules.inboxHours) }
            val banners = MegaphoneInboxItem.banners(raw)
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return
            if (lastRefreshFailed) lastRefreshFailed = false
            applyInbox(banners)
        } catch (error: Throwable) {
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return
            if (host.classifyAuthError(error) == AuthErrorDisposition.cancelled) return
            if (isMissingFunction(error)) {
                // 서버가 아직 안 올라간 창 — 필터를 끄고 지금처럼 메시지로 보이게 한다.
                if (capability != Capability.unavailable) capability = Capability.unavailable
                if (knownMessageIDs.isNotEmpty()) knownMessageIDs = emptySet()
                return
            }
            lastRefreshFailed = true
        }
    }

    /** inbox 한 벌을 반영한다(네트워크 없음). */
    private fun applyInbox(banners: List<MegaphoneBanner>) {
        val ids = banners.mapNotNull { it.messageID }.toSet()
        if (!knownMessageIDs.containsAll(ids)) knownMessageIDs = knownMessageIDs + ids
        val next = if (unreadSummaryV2Missing) Capability.unavailable else Capability.available
        if (capability != next) capability = next
        val now = clock()
        for (banner in banners.sortedBy { it.createdAt }) offer(banner, fromPush = false, atFront = false, now = now)
        pump()
    }

    // ---------------------------------------------------------------- 띄우기

    /**
     * 푸시로 안 확성기를 띄운다(앱이 앞에 있을 때 받은 푸시 · 푸시를 눌러 들어옴). **24시간 안이면 신선도를 무시**하고 줄 맨 앞에 선다.
     * 이미 본 확성기는 다시 안 띄운다. 띄운 뒤 refresh 로 id·아바타를 맞춘다(필터도 그때 켜진다).
     */
    fun presentFromPush(
        megaphoneID: String,
        senderName: String?,
        body: String,
        senderID: String? = null,
        messageID: String? = null,
        createdAt: SwiftDate? = null,
    ) {
        val now = clock()
        if (megaphoneID.isEmpty()) return
        val text = MegaphoneBanner.displayBody(body) ?: return
        val created = createdAt ?: now
        if (!MegaphoneBannerRules.isPresentable(created, now, fromPush = true)) return
        val name = senderName.orEmpty().trim()
        val banner = MegaphoneBanner(
            messageID = messageID, megaphoneID = megaphoneID, senderID = senderID,
            senderName = name.ifEmpty { MegaphoneBanner.fallbackSenderName },
            senderAvatarURL = null, body = text, createdAt = created,
        )
        offer(banner, fromPush = true, atFront = true, now = now)
        pump()
        if (host?.session != null) scope.launch { refresh() }
    }

    /**
     * 보낸 직후 내 화면에 "이렇게 떴어요" 배너를 한 번 띄운다(서버 fan-out 에 나는 없으니 중복이 아니다). 줄 맨 앞에 선다.
     * [megaphoneID] 를 주면(전송 응답의 id) 본 것으로 기록한다.
     */
    fun presentOwn(body: String, senderName: String, senderAvatarURL: String? = null, megaphoneID: String? = null) {
        val text = MegaphoneBanner.displayBody(body) ?: return
        val now = clock()
        val id = megaphoneID?.ifEmpty { null } ?: (LOCAL_ID_PREFIX + Uuid.random().toString().lowercase())
        val banner = MegaphoneBanner(
            messageID = null, megaphoneID = id, senderID = host?.session?.userID,
            senderName = senderName.ifEmpty { MegaphoneBanner.fallbackSenderName },
            senderAvatarURL = senderAvatarURL, body = text, createdAt = now, isOwn = true,
        )
        offer(banner, fromPush = false, atFront = true, now = now)
        pump()
    }

    /** 지금 배너를 닫는다([닫기] · [답장] · 위로 쓸기 · 8초). 다음 장은 0.4초 뒤. */
    fun dismissCurrent() {
        if (current == null) return
        current = null
        if (isTimerPaused) isTimerPaused = false
        currentFromPush = false
        currentDeadline = null
        timerToken += 1
        inGap = true
        val token = timerToken
        schedule(MegaphoneBannerRules.gap) {
            if (timerToken == token) {
                inGap = false
                pump()
            }
        }
    }

    /** 타이머를 멈춘다(폰: 누르고 있음). */
    fun pauseTimer() {
        if (current == null || isTimerPaused) return
        isTimerPaused = true
        val now = clock()
        pausedRemaining = maxOf(0.0, (currentDeadline ?: now).timeIntervalSince(now))
        timerToken += 1
    }

    /** 다시 센다 — 남은 시간과 3초 중 긴 쪽. */
    fun resumeTimer() {
        if (current == null || !isTimerPaused) return
        isTimerPaused = false
        startTimer(maxOf(pausedRemaining, MegaphoneBannerRules.resumeMinimum))
    }

    /** [isBannerDeferred] 가 바뀌었다. 미루기 시작이면 떠 있던 배너를 줄 맨 앞으로 되돌리고, 풀렸으면 **신선한 것만** 띄운다. */
    fun deferralChanged() {
        if (isBannerDeferred()) {
            val showing = current ?: return
            timerToken += 1
            current = null
            if (isTimerPaused) isTimerPaused = false
            currentDeadline = null
            queue = listOf(showing) + queue
            if (currentFromPush) fromPushIDs.add(showing.megaphoneID)
            currentFromPush = false
        } else {
            pump()
        }
    }

    /** 로그아웃·계정 전환. 줄·id·필터·기록 캐시를 비우고, 나가 있던 응답과 타이머는 세대로 버린다. 본 것 기록 자체는 계정 키에 남는다. */
    fun reset() {
        resetGeneration += 1
        timerToken += 1
        capability = Capability.unknown
        knownMessageIDs = emptySet()
        checkedMessageIDs = emptySet()
        current = null
        queue = emptyList()
        isTimerPaused = false
        unreadSummaryV2Missing = false
        lastRefreshFailed = false
        fromPushIDs = LinkedHashSet()
        currentFromPush = false
        verifyQueue = emptySet()
        refreshJob = null
        rerunRequested = false
        currentDeadline = null
        pausedRemaining = 0.0
        inGap = false
        seenCache = null
        memorySeen = emptyList()
    }

    // ---------------------------------------------------------------- 본 것 기록

    /** 이 계정의 본 것 기록(오래된 것 → 최근, 최대 100). */
    val seenMegaphoneIDs: List<String> get() = seenIDs()

    fun hasSeen(megaphoneID: String): Boolean = megaphoneID in seenIDs()

    private fun seenIDs(): List<String> {
        val userID = host?.session?.userID?.ifEmpty { null } ?: return memorySeen
        seenCache?.let { (cachedUser, ids) -> if (cachedUser == userID) return ids }
        val ids = defaults?.getString(MegaphoneBannerRules.seenKey(userID))?.split('\n')?.filter { it.isNotEmpty() } ?: emptyList()
        seenCache = userID to ids
        return ids
    }

    private fun recordSeen(megaphoneID: String) {
        if (megaphoneID.startsWith(LOCAL_ID_PREFIX)) return
        val ids = (seenIDs().filter { it != megaphoneID } + megaphoneID).takeLast(MegaphoneBannerRules.seenLimit)
        val userID = host?.session?.userID?.ifEmpty { null }
        if (userID != null) {
            seenCache = userID to ids
            defaults?.putString(MegaphoneBannerRules.seenKey(userID), ids.joinToString("\n"))
        } else {
            memorySeen = ids
        }
    }

    // ---------------------------------------------------------------- 줄 · 타이머

    /** 한 건을 줄에 넣는다. 같은 확성기가 떠 있거나 줄에 있으면 정보만 얹는다 · 이미 봤거나 묵었으면 버린다. */
    private fun offer(banner: MegaphoneBanner, fromPush: Boolean, atFront: Boolean, now: SwiftDate) {
        current?.let { showing ->
            if (showing.megaphoneID == banner.megaphoneID) {
                val merged = showing.merged(banner)
                if (merged != showing) current = merged
                return
            }
        }
        val index = queue.indexOfFirst { it.megaphoneID == banner.megaphoneID }
        if (index >= 0) {
            val merged = queue[index].merged(banner)
            if (merged != queue[index]) queue = queue.toMutableList().also { it[index] = merged }
            if (fromPush) fromPushIDs.add(banner.megaphoneID)
            return
        }
        if (hasSeen(banner.megaphoneID) || !MegaphoneBannerRules.isPresentable(banner.createdAt, now, fromPush)) return
        if (fromPush) fromPushIDs.add(banner.megaphoneID)
        queue = if (atFront) {
            listOf(banner) + queue
        } else {
            val at = queue.indexOfFirst { it.createdAt > banner.createdAt }.let { if (it < 0) queue.size else it }
            queue.toMutableList().also { it.add(at, banner) }
        }
    }

    /** 띄울 수 있으면 줄 맨 앞을 띄운다. 묵은 것(신선도 밖)은 이때 버린다 — 미룸이 풀린 뒤에도 신선한 것만 뜬다. */
    private fun pump() {
        if (current != null || inGap || isBannerDeferred()) return
        val now = clock()
        val kept = queue.filter { MegaphoneBannerRules.isPresentable(it.createdAt, now, fromPush = it.megaphoneID in fromPushIDs) }
        if (kept.size != queue.size) {
            queue = kept
            fromPushIDs.retainAll(kept.map { it.megaphoneID }.toSet())
        }
        if (queue.isEmpty()) return
        val next = queue.first()
        queue = queue.drop(1)
        currentFromPush = fromPushIDs.remove(next.megaphoneID)
        current = next
        if (isTimerPaused) isTimerPaused = false
        recordSeen(next.megaphoneID)
        startTimer(MegaphoneBannerRules.displaySeconds)
    }

    private fun startTimer(delaySeconds: Double) {
        timerToken += 1
        val token = timerToken
        currentDeadline = clock().addingTimeInterval(delaySeconds)
        schedule(delaySeconds) {
            if (timerToken == token && current != null && !isTimerPaused) dismissCurrent()
        }
    }

    companion object {
        /** 옛 안 읽음 요약(확성기 줄도 센다 — V0333 관문 함수, 옛 앱이 쓴다). */
        const val UNREAD_SUMMARY_V1 = "message_unread_summary"

        /** 새 안 읽음 요약(확성기 줄을 안 센다). */
        const val UNREAD_SUMMARY_V2 = "message_unread_summary_v2"

        private const val LOCAL_ID_PREFIX = "local-"

        private fun isMissingFunction(error: Throwable): Boolean = BlockReportRules.isMissingFunction(serviceErrorFacts(error))
    }
}
