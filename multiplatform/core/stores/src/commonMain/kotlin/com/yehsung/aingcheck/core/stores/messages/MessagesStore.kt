// 원본: Sources/CheckMobileKit/Messages/MessagesStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMessageHistory
import com.yehsung.aingcheck.core.net.fetchMessageHistoryWithPokes
import com.yehsung.aingcheck.core.net.fetchMessageHistoryWithReads
import com.yehsung.aingcheck.core.net.fetchMessageUnreadSummary
import com.yehsung.aingcheck.core.net.fetchPokeDirectory
import com.yehsung.aingcheck.core.net.markConversationRead
import com.yehsung.aingcheck.core.net.markMessagesRead
import com.yehsung.aingcheck.core.net.sendMessage
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.MessageBody
import com.yehsung.aingcheck.core.rules.text.MessageBodyValidation
import com.yehsung.aingcheck.core.rules.text.MessageHistoryLoad
import com.yehsung.aingcheck.core.rules.text.MessageHistoryReadSnapshot
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.rules.text.MessageOptimisticRead
import com.yehsung.aingcheck.core.rules.text.MessageThread
import com.yehsung.aingcheck.core.rules.text.MessageThreadBuilder
import com.yehsung.aingcheck.core.rules.text.MessageUnreadRules
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.rules.text.sortedForMessageHistory
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.BlockedUser
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogEntry
import com.yehsung.aingcheck.core.wire.models.MessagePokeLogKind
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.core.wire.models.sortedForPokeDisplay
import com.yehsung.aingcheck.core.wire.models.toPokeDirectoryEntries
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 라우터가 아는 "지금 보이는 대화"(Swift `context.router.visibleConversationPeerID` — 라우터는 feature/phone 몫이라 문만 둔다). */
interface MessagesRouterLink {
    var visibleConversationPeerID: String?
}

/**
 * 메시지 탭 스토어(SPEC-ios §3.3 · SPEC-ios-build D4).
 *
 * 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
 * - 생성 — 앱 조립이 로그인 여부와 무관하게 한 번 만든다. 네트워크를 부르지 않는다.
 * - [appDidBecomeActive] · [appDidEnterBackground] · [reset](로그아웃·치명 만료로 세대가 바뀐 직후) · [badgeCount] · [didReceiveMessagePush].
 * - 실시간 신호: 폰 실시간 러너(W2-f)가 [realtimeMessageActivity] · [realtimeMessageRead] 를 부른다(Swift 는 init 에서 등록 — 여기는
 *   조립이 잇는다. 둘 다 스스로 로그인·active 를 확인한다).
 *
 * ── 이 스토어가 지키는 것(맥 `WorkTimerStoreMessages` 의 v0.3.30~0.3.31 규칙을 폰 수명으로 옮긴 것) ──
 * ① **take_pokes 를 부르지 않는다.** 새 메시지는 실시간 신호·푸시·화면 표시가 **조회**(요약 · 이력)로 갚는다(서비스에 그 메서드가 없다).
 * ② **읽음은 서버가 판정한다.** 안 읽음은 서버 플래그, 경계는 메시지 id, 선후는 요청 일련번호다 — 시각을 비교하지 않는다.
 *    읽음을 올리는 자리는 [evaluateReadMarking] 하나다: **앱이 active 이고 그 대화 화면이 떠 있을 때만**.
 * ③ **메시지 활동 새로고침은 겹치지 않는다**([requestActivityRefresh] — 돌고 있으면 뒤따르는 한 번으로 합친다).
 *    그래도 모든 이력 응답은 **띄운 순서 번호**로 거른다 — 먼저 띄운 늦은 응답이 나중 응답이 그린 새 줄을 지우지 않는다(맥 M4 원칙).
 * ④ **열린 대화는 신호 뒤 곧바로 이력을 받는다**(스로틀 없음). 닫힌 대화는 요약만 받고 이력은 "낡음"으로 적어 다음에 화면이 서는 순간 받는다.
 * ⑤ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 대화·점·경계·입력칸을 건드리지 않는다.
 * ⑥ (데스크톱, Windows 공용 패치 3) take_pokes 를 **부르는 쪽은 데스크톱 찌르기 갈래**다. 이 스토어는 그 갈래가 소비해 넘긴 행을 받아
 *    기록에 곧바로 넣는 문만 연다([insertConsumedPokes] · [receiveConsumedMessages] · [refreshConversationAfterPokeSent]) — ① 은 그대로다.
 *    폰은 이 문을 부르지 않는다(즉시 삽입 장부가 비어 있으면 이력 반영은 예전과 글자 그대로 같다).
 *
 * 실행 규약(Swift `@MainActor`): 공개 함수는 한 디스패처(앱 = 메인, 시험 = runTest)에서 부른다. 띄우는 작업은 [scope] 에서 돈다.
 * 노출(K8): Swift 이름 그대로의 값(`mutableStateOf` — Compose 가 읽는 순간 구독한다).
 */
@OptIn(ExperimentalUuidApi::class)
class MessagesStore(
    val context: SessionContext,
    parentScope: CoroutineScope,
    /** 이름 비교(Swift `localizedStandardCompare` — W1-c `sort` 골든의 [com.yehsung.aingcheck.core.rules.text.NaturalKoCollation]). */
    private val collation: Collation,
    /** 자리 말풍선 id(Swift `UUID().uuidString.lowercased()`). 시험이 고정한다 — 서버로 나가지 않는다. */
    private val newLocalID: () -> String = { Uuid.random().toString().lowercase() },
    /** 확성기 호스트(Swift `context.gomokuHost` — 루비 미러를 오목·체스·상점과 한 칸으로 나눠 쓴다). 조립이 넘긴다. */
    megaphoneHost: MegaphoneHost? = null,
) {
    val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))

    /** 확성기(📢 1.0.7) 작성 스토어 — 맥과 같은 코어 스토어. 화면은 메시지 탭 위 📢 버튼의 시트. */
    val megaphone: MegaphoneStore = MegaphoneStore(megaphoneHost, scope, clock = { context.clock.now() })

    /** 지금 탭 스토어(약참조 자리 — Swift `context.links.now`). 사람들의 근무 여부·센터 판의 재료다. 조립이 채운다. */
    var nowStore: NowStore? = null

    /** 라우터(조립이 채운다). */
    var router: MessagesRouterLink? = null

    // ---------------------------------------------------------------- 이력 · 읽음

    /** 이력(오래된 것 → 최신, 같은 초는 서버 순서). 모든 대화가 이 한 배열에서 묶인다([threads]). */
    var history: List<MessageEntry> by mutableStateOf(emptyList())
        private set

    /** 읽음 칸을 실어 온 마지막 이력의 사실(요청 번호 · 서버 순서). null = 아직 없거나 서버가 읽음을 모른다. */
    var historySnapshot: MessageHistoryReadSnapshot? by mutableStateOf(null)
        private set

    /** 서버가 읽음 기능을 아는가(`message_history_with_reads` 성공). false 면 화면은 1 을 그리지 않는다. */
    var readReceiptsAvailable: Boolean by mutableStateOf(false)
        private set
    var historyLoaded: Boolean by mutableStateOf(false)
        private set
    var historyLoading: Boolean by mutableStateOf(false)
        private set
    var historyFailed: Boolean by mutableStateOf(false)
        private set
    var summary: MessagesSummarySnapshot? by mutableStateOf(null)
        private set
    var optimisticReads: Map<String, MessageOptimisticRead> by mutableStateOf(emptyMap())
        private set

    /** 읽음을 모르는 옛 서버용 도장(대화를 본 순간, 1970 기준 초). 서버가 읽음을 알면 쓰이지 않는다. */
    var legacyReadStamps: Map<String, Double> by mutableStateOf(emptyMap())
        private set

    // ---------------------------------------------------------------- 찌르기 기록 (1.0.13 · message_history_with_pokes)

    /** 창(24h) 안의 찌르기 기록 — 시간순, 받은 것·보낸 것 모두. 옛 서버면 언제나 빈 배열. 메시지([history])와 **섞지 않는다**. */
    var pokeLog: List<MessagePokeLogEntry> by mutableStateOf(emptyList())
        private set

    /** 서버가 찌르기 기록을 아는가(`message_history_with_pokes` 성공). */
    var pokeLogAvailable: Boolean by mutableStateOf(false)
        private set

    /** 행 id → 서버 시각 순위(메시지·찌르기 공통). 목록 미리보기와 대화 줄이 같은 표를 읽는다. */
    var pokeChronology: Map<String, Int> by mutableStateOf(emptyMap())
        private set

    var pokeSnapshot: MessageHistoryReadSnapshot? by mutableStateOf(null)
        private set

    /** 찌르기 낙관 읽음(상대별). 메시지와 **따로** 둔다 — 서버 경계가 다른 표(`poke_reads`)다. */
    var optimisticPokeReads: Map<String, MessageOptimisticRead> by mutableStateOf(emptyMap())
        private set

    // ---------------------------------------------------------------- 사람 찾기

    var directory: List<PokeDirectoryEntry> by mutableStateOf(emptyList())
        private set
    var directoryLoaded: Boolean by mutableStateOf(false)
        private set
    var directoryLoading: Boolean by mutableStateOf(false)
        private set
    var directoryFailed: Boolean by mutableStateOf(false)
        private set

    // ---------------------------------------------------------------- 차단 · 신고(동작은 MessagesBlockStore.kt)

    /** 차단해서 **화면에서 걷어낸** 상대(낙관적). 실패하면 빼며 대화가 그대로 되돌아온다. */
    var hiddenBlockedPeerIDs: Set<String> by mutableStateOf(emptySet())
        internal set
    var blockedPeople: List<BlockedUser> by mutableStateOf(emptyList())
        internal set
    var blocksLoaded: Boolean by mutableStateOf(false)
        internal set
    var blocksLoading: Boolean by mutableStateOf(false)
        internal set
    var blocksFailed: Boolean by mutableStateOf(false)
        internal set

    /** 서버가 아직 차단 RPC 를 모른다(PGRST202). 목록 화면이 "고장"이 아니라 "아직"이라고 말한다. */
    var blocksServerNotReady: Boolean by mutableStateOf(false)
        internal set
    var blockingPeerID: String? by mutableStateOf(null)
        internal set
    var unblockingUserIDs: Set<String> by mutableStateOf(emptySet())
        internal set
    var blockNotice: String? by mutableStateOf(null)
        internal set
    var blockNoticeIsError: Boolean by mutableStateOf(false)
        internal set
    var blockedListNotice: String? by mutableStateOf(null)
        internal set
    var isSendingReport: Boolean by mutableStateOf(false)
        internal set
    var reportNotice: String? by mutableStateOf(null)
        internal set

    // ---------------------------------------------------------------- 화면 · 입력

    var isAppActive: Boolean by mutableStateOf(false)
        private set
    var isListVisible: Boolean by mutableStateOf(false)
        private set

    /** 지금 떠 있는 대화 화면의 상대(여럿이면 마지막으로 선 것). */
    var openConversationPeerID: String? by mutableStateOf(null)
        private set

    /** 상대별 입력 중인 글(대화를 나갔다 와도 남는다 · 로그아웃이면 비운다). */
    var drafts: Map<String, String> by mutableStateOf(emptyMap())
        private set
    var pendingOutgoing: List<MessagesPendingOutgoing> by mutableStateOf(emptyList())
        private set

    /** 상대별 전송 실패 안내(입력칸 위 한 줄). 성공은 문구를 세우지 않는다. */
    // INV-MessagesStore-8c962db9 이식: 설정자는 이 파일 안으로 닫아 둔다(private set) — 이모티콘 시트의 안내는 시트가 자기 상태로 든다.
    var sendNotices: Map<String, String> by mutableStateOf(emptyMap())
        private set

    /** 전송 왕복 중인가. **한 번에 하나** — 순서가 곧 상대가 읽는 순서라 두 전송을 나란히 띄우지 않는다. */
    var isSending: Boolean by mutableStateOf(false)
        private set

    // ---------------------------------------------------------------- 조절 값(시험이 바꾼다)

    var listRefreshThrottleSeconds: Double = 15.0
    var directoryRefreshThrottleSeconds: Double = 60.0

    /** 읽음 처리 성공 뒤 요약을 다시 받기 전에 기다리는 창(초) — 그 안에 `message_read` 메아리가 오면 그 새로고침이 이 몫을 맡는다. */
    var postMarkRefreshSeconds: Double = 1.5

    /** 기다리기(가상 시간 위에서 도는 `delay`). */
    var sleep: suspend (Double) -> Unit = { seconds -> delay((seconds * 1000).toLong()) }

    private var runtime = MessagesRuntime()

    // ---------------------------------------------------------------- 자리 API

    /**
     * 앱(데스크톱은 플라이아웃)이 앞에 섰다. [activityRefreshThrottleSeconds] 가 0 이하(기본)면 지금처럼 **매번** 요약을 새로 받는다.
     * 양수면 마지막으로 띄운 뒤 그만큼 지나야 받는다 — 맥 팝오버 열기 스로틀(Swift `messageMenuRefreshThrottleSeconds` 60초 ·
     * `refreshMessageActivityOnMenuOpen`, Windows 공용 패치 9). 메시지 화면이 서 있는데 이력이 낡았으면 스로틀 없이 받되
     * **같은 낡음 표시로는 한 번만**이다(Swift m-fix F1 · m-reverify R3). 읽음 판정([evaluateReadMarking])은 스로틀과 무관하게 돈다.
     */
    fun appDidBecomeActive(activityRefreshThrottleSeconds: Double = 0.0) {
        isAppActive = true
        syncRouterVisibility()
        if (!isSignedIn) return
        if (activeRefreshDue(activityRefreshThrottleSeconds)) requestActivityRefresh()
        evaluateReadMarking()
    }

    private fun activeRefreshDue(throttleSeconds: Double): Boolean {
        val owner = runtime
        val now = context.clock.now()
        if (throttleSeconds <= 0.0) {
            owner.lastActiveRefreshAt = now
            return true
        }
        val stale = owner.historyStaleSerial
        val staleScreenBypass = isMessagesScreenVisible && stale != null && stale != owner.activeBypassStaleSerial
        val last = owner.lastActiveRefreshAt
        if (!staleScreenBypass && last != null && now.timeIntervalSince(last) < throttleSeconds) return false
        if (staleScreenBypass) owner.activeBypassStaleSerial = stale
        owner.lastActiveRefreshAt = now
        return true
    }

    fun appDidEnterBackground() {
        isAppActive = false
        syncRouterVisibility()
        runtime.postMarkWindowTask?.cancel()
        runtime.postMarkWindowTask = null
    }

    fun reset() {
        runtime.cancelAll()
        runtime = MessagesRuntime()
        history = emptyList()
        historySnapshot = null
        readReceiptsAvailable = false
        historyLoaded = false
        historyLoading = false
        historyFailed = false
        summary = null
        optimisticReads = emptyMap()
        legacyReadStamps = emptyMap()
        pokeLog = emptyList()
        pokeLogAvailable = false
        pokeChronology = emptyMap()
        pokeSnapshot = null
        optimisticPokeReads = emptyMap()
        directory = emptyList()
        directoryLoaded = false
        directoryLoading = false
        directoryFailed = false
        hiddenBlockedPeerIDs = emptySet()
        blockedPeople = emptyList()
        blocksLoaded = false
        blocksLoading = false
        blocksFailed = false
        blocksServerNotReady = false
        blockingPeerID = null
        unblockingUserIDs = emptySet()
        blockNotice = null
        blockNoticeIsError = false
        blockedListNotice = null
        isSendingReport = false
        reportNotice = null
        isListVisible = false
        openConversationPeerID = null
        drafts = emptyMap()
        pendingOutgoing = emptyList()
        sendNotices = emptyMap()
        isSending = false
        // 확성기 글·요청 id·정보도 계정에 묶인다 — 남기면 다음 사람이 앞 사람의 글을 보고 그 id 로 묻는다.
        megaphone.reset()
        router?.visibleConversationPeerID = null
    }

    /** 탭 배지 = 안 읽은 메시지 수. */
    val badgeCount: Int
        get() = MessagesBadgeRules.unreadCount(visibleHistory, historySnapshot, visibleSummary, optimisticReads, legacyReadStamps)

    /** 메시지 푸시를 받았다(포그라운드). 요약은 곧바로, 그 대화가 떠 있으면 이력도 곧바로. */
    fun didReceiveMessagePush(peerID: String?) {
        if (!isSignedIn) return
        val conversationOpen = peerID != null && peerID == openConversationPeerID
        requestActivityRefresh(includeHistory = isAppActive && conversationOpen)
    }

    // ---------------------------------------------------------------- 파생값

    val isSignedIn: Boolean get() = context.sessionStore.isSignedIn

    /**
     * **차단해 숨긴 상대를 걷어낸 이력.** 묶음·배지·점·개수·말풍선이 전부 이 값을 읽는다 — 거르는 곳이 하나여야 "목록에서는 사라졌는데
     * 배지 숫자는 그대로"가 생기지 않는다.
     */
    val visibleHistory: List<MessageEntry>
        get() {
            val hidden = hiddenBlockedPeerIDs
            if (hidden.isEmpty()) return history
            return history.filter { it.peerUserID !in hidden }
        }

    /** **차단해 숨긴 상대를 걷어낸 요약**(이력만 거르면 요약이 더 새것인 창에서 탭 배지에만 세어진다). */
    val visibleSummary: MessagesSummarySnapshot?
        get() {
            val current = summary ?: return null
            val hidden = hiddenBlockedPeerIDs
            if (hidden.isEmpty()) return current
            val filtered = current.summary.excluding(hidden)
            return if (filtered == current.summary) current else MessagesSummarySnapshot(current.serial, filtered)
        }

    /** 대화 목록(최근 대화순). 같은 초는 서버 순서로 깬다. */
    val threads: List<MessageThread<MessageEntry>>
        get() = MessageThreadBuilder.threads(visibleHistory, historySnapshot?.serverOrder)

    /** **안 읽은 메시지가 있는 상대**(줄 점 · 개수 배지 · 탭 배지의 재료). 찌르기는 여기 들어오지 않는다(정렬용은 [sortUnreadPeerIDs]). */
    val unreadPeerIDs: Set<String>
        get() = MessageUnreadRules.unreadPeerIDs(
            visibleHistory, historySnapshot, visibleSummary?.forRules, optimisticReads, legacyReadStamps,
        )

    /** 차단해 숨긴 상대를 걷어낸 찌르기 기록(이력·요약과 같은 관문). */
    val visiblePokeLog: List<MessagePokeLogEntry>
        get() {
            val hidden = hiddenBlockedPeerIDs
            if (hidden.isEmpty()) return pokeLog
            return pokeLog.filter { it.peerUserID !in hidden }
        }

    /** 한 사람과 오간 찌르기(시간순 — 대화 화면이 메시지 사이에 끼울 재료). */
    fun pokeLog(peerID: String): List<MessagePokeLogEntry> = visiblePokeLog.filter { it.peerUserID == peerID }

    /** **안 본 찌르기가 있는 상대.** 서버 플래그에서 그 스냅샷이 모르는 낙관 읽음을 뺀다. */
    val unreadPokePeerIDs: Set<String>
        get() {
            val snapshot = pokeSnapshot ?: return emptySet()
            return MessagePokeLogRules.unreadPeerIDs(visiblePokeLog, snapshot, optimisticPokeReads)
        }

    /** **정렬 전용** 안 읽음(메시지 ∪ 찌르기). 사용자 결정 2026-10-23 "안 본 찌르기도 안 읽음으로 친다". */
    // INV-MessagesStore-daf1f64e 이식: 이 집합은 배지·"안 읽은 메시지 N"·줄 개수에 쓰지 않는다 — 그 수는 메시지 전용(badgeCount · unreadCountsByPeer).
    val sortUnreadPeerIDs: Set<String>
        get() = MessagesSortRules.combinedUnreadPeerIDs(unreadPeerIDs, unreadPokePeerIDs)

    /**
     * 대화 목록 줄들 — **4단 정렬**(① 근무중+안읽음 → ② 근무안함+안읽음 → ③ 근무중+다읽음 → ④ 근무안함+다읽음), 같은 무리 안은 최근순.
     * 근무 여부를 모르는 창에서는 근무 축을 쓰지 않는다(두 무리). 찌르기만 있는 사람도 한 줄이 선다(사용자 결정 (가)).
     */
    fun threadItems(now: SwiftDate): List<MessagesThreadItem> {
        val board = presenceBoard(now)
        return MessagesThreadListRules.rows(
            threads = threads,
            // INV-MessagesStore-b865a319 이식: 차단 관문을 지난 기록만 넘긴다(visiblePokeLog) — 날것 pokeLog 면 숨긴 사람이 찌르기만으로 줄을 세운다.
            pokes = visiblePokeLog,
            chronology = pokeChronology,
            messageUnreadPeerIDs = unreadPeerIDs,
            pokeUnreadPeerIDs = unreadPokePeerIDs,
            unreadCounts = unreadCountsByPeer,
            workingPeerIDs = MessagesSortRules.workingPeerIDs(board),
            workKnown = board.isKnown,
            now = now,
        )
    }

    /** 상대별 안 읽은 메시지 수(목록 줄 개수 배지). 합 = [badgeCount]. */
    val unreadCountsByPeer: Map<String, Int>
        get() = MessagesBadgeRules.unreadCountsByPeer(visibleHistory, historySnapshot, visibleSummary, optimisticReads, legacyReadStamps)

    /**
     * 사람들의 근무 여부·센터. **서버를 부르지 않는다** — 지금 탭이 받아 두는 팀 상태·사람 목록과, 새 대화 시트가 받은 사람 목록을 겹쳐 읽는다.
     */
    fun presenceBoard(now: SwiftDate): MessagesPresenceBoard {
        val nowStore = nowStore
        val working = nowStore?.workingPeople(now) ?: emptyList()
        val teamIDs: Set<String> = nowStore?.let { store -> if (store.hasLoadedTeam) store.teamMembers.map { it.id }.toSet() else emptySet() }
            ?: emptySet()
        return hidingBlocked(
            MessagesPresenceRules.board(
                nowWorking = working.map { MessagesPresenceRules.Working(it.id, it.name, it.avatarURL, it.center, it.isStale) },
                teamMemberIDs = teamIDs,
                nowDirectory = nowStore?.let { if (it.hasLoadedDirectory) it.directory else null },
                messagesDirectory = if (directoryLoaded) directory else null,
                me = context.sessionStore.userID,
                collation = collation,
            ),
        )
    }

    /** 차단해 숨긴 사람을 판에서 걷어낸다("지금 근무 중 · 바로 말 걸기" 줄이 곧 말 거는 입구 — 상태메시지도 같이 걷는다). */
    private fun hidingBlocked(board: MessagesPresenceBoard): MessagesPresenceBoard {
        val hidden = hiddenBlockedPeerIDs
        if (hidden.isEmpty() || !board.isKnown) return board
        return MessagesPresenceBoard(
            isKnown = board.isKnown,
            peers = board.peers.filterKeys { it !in hidden },
            working = board.working.filter { it.id !in hidden },
            statuses = board.statuses.filterKeys { it !in hidden },
        )
    }

    fun thread(peerID: String): MessageThread<MessageEntry>? = threads.firstOrNull { it.peerUserID == peerID }

    /** 대화 머리 이름: 이력(가장 최신 이름) → **찌르기 기록** → 사람 찾기 목록 → null. */
    fun peerName(peerID: String): String? {
        thread(peerID)?.let { return it.peerName }
        visiblePokeLog.lastOrNull { it.peerUserID == peerID }?.let { return it.peerName }
        return directory.firstOrNull { it.userID == peerID }?.name
    }

    /** 대화 머리. "받는 중" = 이력·사람 찾기 중 하나라도 날아가는 중이거나, 이력이 아직 한 번도 끝나지 않았다(실패도 아님). */
    fun conversationHeader(peerID: String): MessagesConversationHeader {
        val resolving = historyLoading || directoryLoading || (!historyLoaded && !historyFailed)
        return MessagesConversationRules.header(peerName(peerID), resolving)
    }

    fun peerAvatarURL(peerID: String): String? {
        thread(peerID)?.peerAvatarURL?.let { return it }
        visiblePokeLog.lastOrNull { it.peerUserID == peerID }?.peerAvatarURL?.let { return it.absoluteString }
        return directory.firstOrNull { it.userID == peerID }?.avatarURL?.absoluteString
    }

    fun isHiddenByBlock(peerID: String): Boolean = peerID in hiddenBlockedPeerIDs

    /** 대화 화면 줄(말풍선 · 날짜 · **찌르기 기록** · 보내는 중). 찌르기는 차단 관문을 지난 [pokeLog] 에서 온다. */
    fun conversationItems(peerID: String): List<MessagesConversationItem> = MessagesConversationRules.items(
        messages = thread(peerID)?.messages ?: emptyList(),
        pokes = pokeLog(peerID),
        chronology = pokeChronology,
        pending = pendingOutgoing.filter { it.peerUserID == peerID },
        receiptsAvailable = readReceiptsAvailable,
        now = context.clock.now(),
    )

    fun draft(peerID: String): String = drafts[peerID] ?: ""

    fun setDraft(text: String, peerID: String) {
        if (peerID.isEmpty()) return
        if (drafts[peerID] != text) drafts = drafts + (peerID to text)
    }

    /** 확정된 입력으로 지금 보낼 수 있는가(왕복 중 아님 · 본문이 서버 경계 안). 근무 여부는 보지 않는다(서버도 안 본다 — v0.3.30). */
    fun canSend(peerID: String): Boolean {
        if (!isSignedIn || peerID.isEmpty() || isSending) return false
        return MessageBody.validate(draft(peerID)) is MessageBodyValidation.ok
    }

    /** 사람 찾기 목록(검색 + 차단해 숨긴 사람 제외). 정렬 입력은 **언제나 명시적으로** 넘긴다(그 순간의 합친 안 읽음). */
    fun filteredDirectory(query: String): List<PokeDirectoryEntry> {
        val hidden = hiddenBlockedPeerIDs
        val visible = if (hidden.isEmpty()) directory else directory.filter { it.userID !in hidden }
        return MessagesDirectoryRules.filter(visible, query, unreadPeerIDs = sortUnreadPeerIDs, collation = collation)
    }

    // ---------------------------------------------------------------- 화면 사건

    fun listDidAppear() {
        isListVisible = true
        if (!isSignedIn) return
        val now = context.clock.now()
        val due = !historyLoaded || runtime.historyStale ||
            now.timeIntervalSince(runtime.lastListRefreshAt) >= listRefreshThrottleSeconds
        if (!due) return
        runtime.lastListRefreshAt = now
        requestActivityRefresh(includeHistory = true)
    }

    fun listDidDisappear() {
        isListVisible = false
    }

    /** 당겨서 새로고침(스로틀 없음). 끝날 때까지 기다린다. 차단 한 줄은 이 순간 지운다. */
    suspend fun refreshNow() {
        blockNotice = null
        blockNoticeIsError = false
        if (!isSignedIn) return
        runtime.lastListRefreshAt = context.clock.now()
        requestActivityRefresh(includeHistory = true)?.join()
    }

    /** 대화 화면의 [다시 시도]. 이력을 곧바로 다시 받고, 그래도 상대 이름을 모르면 사람 찾기를 다시 받는다(스로틀 무시). */
    suspend fun retryConversation(peerID: String) {
        if (!isSignedIn || peerID.isEmpty()) return
        refreshNow()
        if (!isSignedIn || peerName(peerID) != null) return
        loadDirectory(force = true)
    }

    /** 대화 화면이 섰다. `token` 은 뷰 인스턴스마다 다르다 — 같은 상대의 새 화면이 옛 화면의 사라짐보다 먼저 서도 표시가 꺼지지 않게. */
    fun conversationDidAppear(peerID: String, token: String) {
        if (peerID.isEmpty()) return
        runtime.shownConversations.removeAll { it.first == token }
        runtime.shownConversations += token to peerID
        openConversationPeerID = peerID
        syncRouterVisibility()
        if (!isSignedIn) return
        legacyReadStamps = legacyReadStamps + (peerID to context.clock.now().timeIntervalSince1970)
        evaluateReadMarking()
        requestActivityRefresh(includeHistory = true)
        if (thread(peerID) == null && !directoryLoaded) loadDirectory()
    }

    fun conversationDidDisappear(token: String) {
        runtime.shownConversations.removeAll { it.first == token }
        val current = runtime.shownConversations.lastOrNull()?.second
        if (openConversationPeerID != current) openConversationPeerID = current
        syncRouterVisibility()
    }

    // ---------------------------------------------------------------- 보내기

    /**
     * [보내기]. **조합 중이면 보내지 않는다**(`isComposing` — 화면이 조합을 확정한 뒤 다시 부른다). 보냈으면(왕복을 띄웠으면) true.
     * 누르는 즉시 입력칸을 비우고 자리 말풍선을 세운다. 서버가 거절하면 말풍선을 거두고, 그 사이 새로 친 글이 없으면 입력칸에 글을 되돌린다.
     * 입력칸을 비우는 자리는 **여기 하나다**(이모티콘 입구는 초안을 읽지도 쓰지도 않는다).
     */
    fun sendDraft(peerID: String, isComposing: Boolean): Boolean {
        if (isComposing || !canSend(peerID)) return false
        val validation = MessageBody.validate(draft(peerID)) as? MessageBodyValidation.ok ?: return false
        drafts = drafts + (peerID to "")
        return performSend(validation.value, peerID, restoresDraftOnFailure = true)
    }

    /** 지금 아잉이 이모티콘을 보낼 수 있는가(1.0.12). 입력칸 글을 보지 않는다 — 남는 조건은 [canSend] 첫 줄의 셋과 글자 그대로 같다. */
    fun canSendSticker(peerID: String): Boolean = isSignedIn && peerID.isNotEmpty() && !isSending

    /** 이모티콘 한 장을 보낸다(1.0.12). **입력칸을 거치지 않는다** — 초안을 읽지도 쓰지도 않는다(맥에서 난 결함 둘). */
    fun sendSticker(sticker: AingSticker, peerID: String): Boolean {
        if (!canSendSticker(peerID)) return false
        return performSend(sticker.token, peerID, restoresDraftOnFailure = false)
    }

    /**
     * 본문 하나를 보낸다 — 자리 말풍선 · 재시도 · 세대 가드 · 실패 문구 · 성공 뒤 이력 재조회의 **공통 몸통**. 입구는 둘뿐이다.
     * `restoresDraftOnFailure`: 초안 전송 true · 이모티콘 false(가르는 기준은 글자가 아니라 **의도**다).
     */
    private fun performSend(body: String, peerID: String, restoresDraftOnFailure: Boolean): Boolean {
        val generation = context.generation
        val localID = newLocalID()
        pendingOutgoing = pendingOutgoing +
            MessagesPendingOutgoing(localID, peerID, body, context.clock.now(), MessagesPendingOutgoing.State.sending)
        sendNotices = sendNotices - peerID
        isSending = true
        val service = context.service
        scope.launch {
            var notice: String? = null
            var succeeded = false
            var cancelled = false
            var refreshesDirectory = false
            try {
                val response = context.withSessionRetry { session -> service.sendMessage(session.accessToken, peerID, body) }
                if (generation != context.generation) return@launch
                val outcome = MessageSendOutcome.of(response)
                notice = MessagesSendRules.notice(outcome, response.maxLength)
                succeeded = outcome == MessageSendOutcome.Ok
                refreshesDirectory = outcome == MessageSendOutcome.TargetNotWorking
            } catch (error: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) cancelled = true else notice = MessagesSendRules.connectionNotice
            }
            isSending = false
            if (succeeded) {
                val index = pendingOutgoing.indexOfFirst { it.id == localID }
                if (index >= 0) {
                    pendingOutgoing = pendingOutgoing.toMutableList().also {
                        it[index] = it[index].copy(state = MessagesPendingOutgoing.State.sent(runtime.nextSerial()))
                    }
                }
                // 방금 보낸 말이 서버 행으로 서게 이력을 곧바로 받는다(자리 말풍선은 그 응답이 거둔다).
                requestActivityRefresh(includeHistory = true)
                return@launch
            }
            pendingOutgoing = pendingOutgoing.filter { it.id != localID }
            // 되돌리는 쪽만 입력칸을 만진다. "비어 있을 때만" — 왕복 중에 새로 친 글을 실패한 옛 글이 덮으면 안 된다.
            if (restoresDraftOnFailure && draft(peerID).isEmpty()) drafts = drafts + (peerID to body)
            if (!cancelled && notice != null) sendNotices = sendNotices + (peerID to notice)
            if (refreshesDirectory) loadDirectory(force = true)
        }
        return true
    }

    // ---------------------------------------------------------------- 사람 찾기

    /** `app_user_directory`(읽기). 새 대화 시트가 설 때 · 이름을 모르는 대화가 설 때. */
    fun loadDirectory(force: Boolean = false) {
        if (!isSignedIn || directoryLoading) return
        val now = context.clock.now()
        if (!force && directoryLoaded && now.timeIntervalSince(runtime.lastDirectoryLoadAt) < directoryRefreshThrottleSeconds) return
        runtime.lastDirectoryLoadAt = now
        val generation = context.generation
        directoryLoading = true
        val service = context.service
        scope.launch {
            try {
                val rows = context.withSessionRetry { session -> service.fetchPokeDirectory(session.accessToken) }
                if (generation != context.generation) return@launch
                directoryLoading = false
                // INV-MessagesStore-4c1e9529 이식: 저장 순서에는 안 읽음 축을 넣지 않는다(값을 명시 — 빈 집합). 진짜 정렬 자리는 filteredDirectory 하나.
                //   workKnown = true — 명부 행은 isWorking 을 서버에서 직접 받는다(모르는 창이 없다).
                directory = rows.toPokeDirectoryEntries(RulesWireTextRules)
                    .sortedForPokeDisplay(unreadPeerIDs = emptySet(), workKnown = true, collation = collation)
                directoryLoaded = true
                directoryFailed = false
            } catch (error: Throwable) {
                if (generation != context.generation) return@launch
                directoryLoading = false
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return@launch
                if (error == SupabaseWorkServiceError.DatabaseSchemaMissing) directoryLoaded = true else directoryFailed = true
            }
        }
    }

    // ---------------------------------------------------------------- 메시지 활동 새로고침

    /**
     * 요약 1회(+ 메시지 화면이 떠 있거나 `includeHistory` 면 이력 1회 — 나란히). 돌고 있으면 뒤따르는 한 번으로 합친다(③).
     * 이력을 건너뛰면 "낡음"을 적어 다음에 화면이 설 때 스로틀과 무관하게 받는다(④).
     */
    fun requestActivityRefresh(includeHistory: Boolean = false): Job? {
        if (!isSignedIn) return null
        if (includeHistory || isMessagesScreenVisible) runtime.activityWantsHistory = true else runtime.historyStale = true
        runtime.activityTask?.let { running ->
            runtime.activityAgain = true
            return running
        }
        val generation = context.generation
        val owner = runtime
        val job = scope.launch(start = CoroutineStart.LAZY) {
            do {
                // 루프 안에서 먼저 내린다 — 이번 조회가 도는 동안 온 계기를 지우지 않게.
                owner.activityAgain = false
                val wantsHistory = owner.activityWantsHistory
                owner.activityWantsHistory = false
                if (wantsHistory) {
                    coroutineScope {
                        launch { performLoadSummary() }
                        launch { performLoadHistory() }
                    }
                } else {
                    performLoadSummary()
                }
                if (generation != context.generation) return@launch
            } while (owner.activityAgain)
            owner.activityTask = null
        }
        owner.activityTask = job
        job.start()
        return job
    }

    /** 이력 1회. 모든 이력 조회가 이 문을 지난다 — **띄운 순서 번호**가 반영 여부를 정한다(③). */
    suspend fun performLoadHistory() {
        if (!isSignedIn) return
        val generation = context.generation
        val owner = runtime
        val serial = owner.nextSerial()
        owner.lastHistoryLaunchSerial = serial
        owner.historyInFlight += 1
        if (!historyLoading) historyLoading = true
        try {
            val conversation = context.withSessionRetry { session -> fetchConversationLoad(session.accessToken) }
            val loaded = conversation.history
            if (generation != context.generation) return
            // 더 나중에 띄운 조회가 이미 반영됐다 — 이 응답은 그보다 낡은 서버 상태다.
            if (serial <= owner.lastAppliedHistorySerial) return
            owner.lastAppliedHistorySerial = serial
            owner.historyStaleSerial?.let { staleSince -> if (serial > staleSince) owner.historyStaleSerial = null }
            val previousIDs = history.map { it.id }.toSet()
            // 즉시 삽입(맥 v0.3.31 M4 — 데스크톱만 넣는다)한 도착분 중 **이 조회보다 나중에 넣은 것**은 남긴다. 장부가 비면(폰) 빈 목록 · 빈 표라
            // 예전 정렬과 글자 그대로 같다. 남긴 것은 서버가 모르는 말이라 같은 초 안에서 그 뒤에 **도착 순서**로 선다(m4-fix).
            val kept = owner.survivingLocalArrivals(serial, history, loaded.entries)
            val sorted = (loaded.entries + kept).sortedForMessageHistory(
                if (loaded.hasReadReceipts) loaded.serverOrder else null,
                owner.localArrivalSerials,
            )
            if (history != sorted) history = sorted
            if (loaded.hasReadReceipts) {
                val snapshot = MessageHistoryReadSnapshot(serial, loaded.serverOrder)
                if (historySnapshot != snapshot) historySnapshot = snapshot
                if (!readReceiptsAvailable) readReceiptsAvailable = true
            } else {
                if (historySnapshot != null) historySnapshot = null
                if (readReceiptsAvailable) readReceiptsAvailable = false
            }
            applyPokeLog(conversation, serial)
            val reconciled = MessagesPendingRules.reconcile(pendingOutgoing, previousIDs, sorted, serial)
            if (reconciled != pendingOutgoing) pendingOutgoing = reconciled
            if (!historyLoaded) historyLoaded = true
            if (historyFailed) historyFailed = false
            // 새 이력 — 떠 있는 대화에 서버 기준 안 읽은 말이 있으면 올린다(새로 도착한 말 포함).
            evaluateReadMarking()
        } catch (error: Throwable) {
            if (generation != context.generation) return
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
            if (error == SupabaseWorkServiceError.DatabaseSchemaMissing) {
                // 세 이력 함수가 다 없는 서버 — 실패가 아니라 "받을 것이 없다". 빈 이력으로 조용히 접는다.
                if (!historyLoaded) historyLoaded = true
                if (readReceiptsAvailable) readReceiptsAvailable = false
                applyPokeLog(MessageConversationLoad(MessageHistoryLoad(emptyList(), hasReadReceipts = false), pokes = null), serial)
                owner.historyStaleSerial = null
            } else if (!historyFailed) {
                historyFailed = true
            }
        } finally {
            if (generation == context.generation) {
                owner.historyInFlight -= 1
                if (owner.historyInFlight == 0 && historyLoading) historyLoading = false
            }
        }
    }

    /**
     * 새 이력(메시지 + 찌르기 기록)을 반영한다. `pokes == null`(옛 서버로 접음)이면 찌르기 쪽을 **전부 비운다** — 서버가 모르는 동안 옛 기록이
     * 남아 있으면 정렬이 사라진 근거로 사람을 올리고, 대화 줄에 유령 찌르기가 남는다.
     */
    private fun applyPokeLog(conversation: MessageConversationLoad, serial: Int) {
        val pokes = conversation.pokes
        if (pokes == null) {
            if (pokeLog.isNotEmpty()) pokeLog = emptyList()
            if (pokeLogAvailable) pokeLogAvailable = false
            if (pokeChronology.isNotEmpty()) pokeChronology = emptyMap()
            if (pokeSnapshot != null) pokeSnapshot = null
            runtime.pokeLocalArrivalSerials.clear()
            return
        }
        // 즉시 넣은 찌르기(데스크톱 take_pokes 소비분) 중 이 조회보다 나중에 넣은 것은 남긴다(Swift applyMessagePokeLog 와 같은 규칙).
        // 장부가 비면(폰) 빈 목록 · 빈 표라 예전 정렬과 같다.
        val kept = runtime.survivingLocalPokeArrivals(serial, pokeLog, pokes)
        val sorted = MessagePokeLogRules.sorted(pokes + kept, conversation.chronology, runtime.pokeLocalArrivalSerials)
        if (pokeLog != sorted) pokeLog = sorted
        if (pokeChronology != conversation.chronology) pokeChronology = conversation.chronology
        // 찌르기 경계 비교는 **같은 표**(메시지·찌르기 공통 순위)로 한다 — 메시지 서버 순서에는 찌르기 id 가 없다.
        val snapshot = MessageHistoryReadSnapshot(serial, conversation.chronology)
        if (pokeSnapshot != snapshot) pokeSnapshot = snapshot
        if (!pokeLogAvailable) pokeLogAvailable = true
    }

    /**
     * `message_history_with_pokes` → 없는 서버(404/PGRST202)면 **지금까지의 사슬 그대로**(`message_history_with_reads` → `message_history`).
     * 폴백은 캐시하지 않는다(서버가 배포되는 순간 다음 조회부터 새 길로 간다).
     */
    private suspend fun fetchConversationLoad(accessToken: String): MessageConversationLoad {
        val service = context.service
        return try {
            MessageConversationLoad.of(
                service.fetchMessageHistoryWithPokes(accessToken, MessageNoticeText.historyHours.toLong(), MessageNoticeText.historyLimit.toLong()),
            )
        } catch (error: SupabaseWorkServiceError) {
            if (!isMissingFunction(error)) throw error
            fetchHistoryPreferringReads(accessToken)
        }
    }

    /** `message_history_with_reads` → 없는 서버(404/PGRST202)면 옛 `message_history`(읽음 모름). */
    private suspend fun fetchHistoryPreferringReads(accessToken: String): MessageConversationLoad {
        val service = context.service
        val hours = MessageNoticeText.historyHours.toLong()
        val limit = MessageNoticeText.historyLimit.toLong()
        return try {
            MessageConversationLoad.legacy(service.fetchMessageHistoryWithReads(accessToken, hours, limit), hasReadReceipts = true)
        } catch (error: SupabaseWorkServiceError) {
            if (!isMissingFunction(error)) throw error
            MessageConversationLoad.legacy(service.fetchMessageHistory(accessToken, hours, limit), hasReadReceipts = false)
        }
    }

    /** 요약 1회. */
    suspend fun performLoadSummary() {
        if (!isSignedIn) return
        val generation = context.generation
        val owner = runtime
        val serial = owner.nextSerial()
        owner.lastSummaryLaunchSerial = serial
        try {
            val response = context.withSessionRetry { session -> context.service.fetchMessageUnreadSummary(session.accessToken) }
            if (generation != context.generation) return
            val value = response.summary ?: return
            // 늦게 온 옛 요약이 새 요약을 덮지 않게(이력과 같은 번호 규칙).
            if (serial <= (summary?.serial ?: 0)) return
            val snapshot = MessagesSummarySnapshot(serial, value)
            if (summary != snapshot) summary = snapshot
        } catch (error: Throwable) {
            // 함수 없음·장애 — 요약 없이 이력(또는 옛 도장) 기준으로 산다. 문구를 세우지 않는다(배지 재료일 뿐이다).
        }
    }

    // ---------------------------------------------------------------- 읽음

    /**
     * **읽음을 올리는 유일한 자리**(②). 앱 active · 그 대화 화면이 떠 있음 · 서버 기준 안 본 것(메시지 **또는** 찌르기)이 있음 — 셋이 다 맞을 때만.
     * 두 갈래는 한 왕복(`mark_conversation_read`)으로 같이 올린다.
     */
    fun evaluateReadMarking() {
        if (!isSignedIn || !isAppActive) return
        val peer = openConversationPeerID ?: return
        val through = historySnapshot?.let { snapshot ->
            MessageUnreadRules.markTarget(peer, visibleHistory, snapshot, optimisticReads[peer])
        }
        // INV-MessagesStore-47fda127 이식: 찌르기 경계는 화면에 보인 마지막 받은 찌르기 id 다 — 지금 시각으로 올리지 않는다.
        val pokeThrough = pokeSnapshot?.let { snapshot ->
            MessagePokeLogRules.markTarget(peer, visiblePokeLog, snapshot, optimisticPokeReads[peer])
        }
        if (through == null && pokeThrough == null) return
        markRead(peer, through, pokeThrough)
    }

    /** 읽음 처리 1회. 상대별로 겹치지 않는다. 응답 전에 낙관 읽음으로 점·배지를 곧바로 끈다 — 실패해도 되돌리지 않는다(정산만). */
    private fun markRead(peer: String, through: String?, pokeThrough: String?) {
        if (peer in runtime.markInFlight) {
            runtime.markAgain += peer
            return
        }
        runtime.markInFlight += peer
        if (through != null) {
            val record = MessageOptimisticRead(through, runtime.nextSerial())
            if (optimisticReads[peer] != record) optimisticReads = optimisticReads + (peer to record)
        }
        if (pokeThrough != null) {
            val record = MessageOptimisticRead(pokeThrough, runtime.nextSerial())
            if (optimisticPokeReads[peer] != record) optimisticPokeReads = optimisticPokeReads + (peer to record)
        }
        val generation = context.generation
        val service = context.service
        scope.launch {
            var succeeded = false
            try {
                // 찌르기만 올릴 때는 p_through_message 를 **싣지 않는다**(null 인 갈래는 움직이지 않는다 — 와이어가 키를 뺀다).
                val response = context.withSessionRetry { session ->
                    service.markConversationRead(session.accessToken, peer, through, pokeThrough)
                }
                succeeded = response.isOK
            } catch (error: Throwable) {
                if (error is SupabaseWorkServiceError && isMissingFunction(error)) {
                    // 옛 서버 — 메시지 갈래만 옛 함수로 접는다. 경계가 없으면 아무것도 올리지 않는다
                    // (옛 mark_messages_read 는 p_through 가 null 이면 그 사람의 최신까지 올린다).
                    if (through != null) {
                        try {
                            val response = context.withSessionRetry { session -> service.markMessagesRead(session.accessToken, peer, through) }
                            succeeded = response.isOK
                        } catch (_: Throwable) {
                            // "이번엔 못 올렸다".
                        }
                    }
                }
                // 취소·네트워크 — "이번엔 못 올렸다". 낙관 표시는 되돌리지 않는다.
            }
            if (generation != context.generation) return@launch
            runtime.markInFlight -= peer
            settleOptimisticRead(peer, through, pokeThrough, succeeded)
            if (succeeded) schedulePostMarkRefresh()
            if (runtime.markAgain.remove(peer)) evaluateReadMarking()
        }
    }

    private fun settleOptimisticRead(peer: String, through: String?, pokeThrough: String?, succeeded: Boolean) {
        if (through != null) {
            val record = optimisticReads[peer]
            if (record != null && record.throughID == through && record.settledSerial == null) {
                optimisticReads = optimisticReads + (peer to record.copy(settledSerial = runtime.nextSerial(), failed = !succeeded))
            }
        }
        if (pokeThrough != null) {
            val record = optimisticPokeReads[peer]
            if (record != null && record.throughID == pokeThrough && record.settledSerial == null) {
                optimisticPokeReads = optimisticPokeReads + (peer to record.copy(settledSerial = runtime.nextSerial(), failed = !succeeded))
            }
        }
    }

    /** 읽음 성공 뒤 요약을 한 번 — 창 안에 다른 새로고침(메아리 신호 등)이 이미 떴으면 그것이 맡는다. */
    private fun schedulePostMarkRefresh() {
        val owner = runtime
        owner.postMarkPendingSerial = owner.serial
        if (owner.postMarkWindowTask != null) return
        val generation = context.generation
        val seconds = postMarkRefreshSeconds
        val wait = sleep
        owner.postMarkWindowTask = scope.launch {
            wait(seconds)
            if (generation != context.generation) return@launch
            owner.postMarkWindowTask = null
            if (owner.lastSummaryLaunchSerial > owner.postMarkPendingSerial) return@launch
            requestActivityRefresh()
        }
    }

    // ---------------------------------------------------------------- take_pokes 소비분(데스크톱 — Windows 공용 패치 3)

    /**
     * take_pokes 가 **소비한** 행 중 찌르기(일반 · 울트라)를 기록에 곧바로 넣는다(데스크톱 drain 이 부른다). 반환값은 넣은 개수.
     * 원본: Sources/check/WorkTimerStoreMessagePokes.swift `insertConsumedPokesIntoLog(rows:)`(106-150).
     *
     *  · 서버가 찌르기 기록을 모르면([pokeSnapshot] 이 null) 넣지 않는다 — 넣으면 다음 이력에서 사라지는 줄이 된다.
     *  · 종류는 이력 디코더와 같은 규칙([MessagePokeLogKind.of])으로 가른다 — 'message' · 모르는 값은 건너뛴다. kind 가 없는 행은 옛 서버의
     *    일반 찌르기다. ([PokeKind.of] 는 말풍선을 위해 모르는 값을 일반으로 접는다 — 그 규칙을 쓰면 미래 종류가 점을 단 채 맨 위에 머문다.)
     *  · 빈 id · 빈 보낸이 · 이미 있는 id · 차단으로 걷어낸 사람([hiddenBlockedPeerIDs]) · 보관 창(24시간) 밖은 넣지 않는다.
     *  · 받은 것이므로 안 읽음이다. 넣은 줄마다 도착 번호를 하나씩(행 순서 = 서버 created_at 순서) 적는다 — 그보다 먼저 띄운 이력 응답이
     *    지우지 않게(`survivingLocalPokeArrivals`), 그리고 같은 초 동률의 도착 순서표로. 넣은 뒤 곧바로 읽음 판정을 돈다.
     */
    fun insertConsumedPokes(rows: List<TakenPokeRow>): Int {
        if (pokeSnapshot == null || rows.isEmpty()) return 0
        val horizon = context.clock.now().addingTimeInterval(-MessageNoticeText.historyHours.toDouble() * 3600.0)
        val known = pokeLog.mapTo(HashSet()) { it.id }
        val additions = ArrayList<MessagePokeLogEntry>()
        for (row in rows) {
            val kind = MessagePokeLogKind.of(row.kind ?: "normal") ?: continue
            if (row.id.isEmpty() || row.fromUser.isEmpty() || row.id in known || row.fromUser in hiddenBlockedPeerIDs) continue
            val createdAt = SwiftDate(row.createdEpoch.toDouble())
            if (createdAt < horizon) continue
            known += row.id
            additions += MessagePokeLogEntry(
                id = row.id,
                peerUserID = row.fromUser,
                peerName = row.fromDisplayName.ifEmpty { "사용자" },
                peerAvatarURL = SwiftURL.parse(row.fromAvatarUrl),
                createdAt = createdAt,
                isMine = false,
                kind = kind,
                isUnread = true,
            )
        }
        if (additions.isEmpty()) return 0
        val owner = runtime
        for (entry in additions) owner.pokeLocalArrivalSerials[entry.id] = owner.nextSerial()
        val merged = MessagePokeLogRules.sorted(pokeLog + additions, pokeChronology, owner.pokeLocalArrivalSerials)
        if (pokeLog != merged) pokeLog = merged
        evaluateReadMarking()
        return additions.size
    }

    /**
     * take_pokes 가 **소비한** 행에서 메시지를 받아들인다(데스크톱 drain 이 부르는 유일한 문 — 맥 v0.3.31 M4 즉시 삽입).
     * 원본: Sources/check/WorkTimerStoreMessages.swift `receiveConsumedMessages(rows:now:)`(1022).
     *
     *  1. 보이는 대화의 상대가 보낸 행을 **곧바로** 그 대화에 넣는다([insertConsumedMessagesIntoVisibleConversation]) — 신선도와 무관.
     *  2. (맥의 말풍선 큐 — 신선한 것 중 [MessageUnreadRules.isAlreadyRead] 가 아닌 것만 — 는 데스크톱 찌르기 갈래 P13 의 몫이다. [now] 는 그
     *     갈래와 같은 자리를 지키려고 받는다. 1 을 **먼저** 불러야 보고 있는 대화에서 읽음이 오른 말을 그 필터가 거른다.)
     *  3. 소비한 메시지 행이 **하나라도** 있으면 도착 새로고침 1회([requestActivityRefresh] — 요약 + 화면이 보이면 이력).
     */
    @Suppress("UNUSED_PARAMETER")
    fun receiveConsumedMessages(rows: List<TakenPokeRow>, now: SwiftDate) {
        val consumed = consumedMessageEntries(rows, receiptsKnown = readReceiptsAvailable)
        insertConsumedMessagesIntoVisibleConversation(consumed)
        if (consumed.isEmpty()) return
        requestActivityRefresh()
    }

    /**
     * 보이는 대화의 상대가 보낸 것만 **지금** 이력에 넣는다. 반환값은 넣은 개수(Swift `insertConsumedMessagesIntoVisibleConversation`).
     *  · 다른 사람의 말 · 닫힌 대화는 넣지 않는다(도착 새로고침의 요약이 점으로 알린다).
     *  · 이미 있는 id 는 건드리지 않는다(서버 행이 이긴다). 정렬은 이력 응답과 같은 규칙, 넣은 줄마다 도착 번호 하나씩(m4-fix).
     *  · "보이는 대화"는 맥 `mayBeOnScreen`(긍정 신호 하나면 참)의 짝 — 로그인 + 대화 화면 표식([openConversationPeerID]). 읽음은
     *    [evaluateReadMarking] 이 따로 active 를 본다(맥 `isSeen`).
     */
    fun insertConsumedMessagesIntoVisibleConversation(entries: List<MessageEntry>): Int {
        if (entries.isEmpty() || !isSignedIn) return 0
        val peer = openConversationPeerID ?: return 0
        val known = history.mapTo(HashSet()) { it.id }
        val additions = ArrayList<MessageEntry>()
        for (entry in entries) {
            if (entry.peerUserID != peer || entry.id in known) continue
            known += entry.id
            additions += entry
        }
        if (additions.isEmpty()) return 0
        val owner = runtime
        for (entry in additions) owner.localArrivalSerials[entry.id] = owner.nextSerial()
        val merged = (history + additions).sortedForMessageHistory(historySnapshot?.serverOrder, owner.localArrivalSerials)
        if (history != merged) history = merged
        evaluateReadMarking()
        return additions.size
    }

    /**
     * 찌르기를 보냈다(데스크톱 `sendPoke` · `sendUltraPoke` 의 성공 갈래). 그 사람과의 대화가 **떠 있을 때만** 이력을 한 번 받는다 —
     * 보낸 행의 id 는 응답에 없어서 바로 넣을 수 없다. 원본: WorkTimerStoreMessagePokes.swift `refreshConversationAfterPokeSent(to:)`(151-155).
     */
    fun refreshConversationAfterPokeSent(peerID: String): Job? {
        if (!isSignedIn || peerID.isEmpty() || openConversationPeerID != peerID) return null
        return scope.launch { performLoadHistory() }
    }

    // ---------------------------------------------------------------- 실시간 핸들러(폰 실시간 러너가 부른다)

    fun realtimeMessageActivity() {
        if (!isSignedIn || !isAppActive) return
        requestActivityRefresh()
    }

    fun realtimeMessageRead() {
        if (!isSignedIn || !isAppActive) return
        requestActivityRefresh()
    }

    // ---------------------------------------------------------------- 데스크톱 읽음 신호 창(Windows 공용 패치 8)

    /**
     * 읽음 신호(`message_read`)가 합치기 창에 얹혔다 — 데스크톱 실시간 러너가 **신호마다** 부른다(창 타이머는 러너가 든다).
     * 원본: Sources/check/WorkTimerStoreMessages.swift `requestMessageActivityRefreshCoalesced()`(724-746)의 장부 몫.
     * 화면이 안 보이면 이력을 **지금** 낡음으로 적고(`markHistoryStale`), 이 순간을 창의 계기 번호로 둔다(더 나중 신호가 덮는다).
     * 폰의 [realtimeMessageRead] 는 그대로다 — 이것은 `isAppActive` 가드가 없다(트레이 상주라 앱이 안 떠 있어도 점은 갱신한다).
     */
    fun readSignalArrived() {
        if (!isSignedIn) return
        val owner = runtime
        if (!isMessagesScreenVisible) owner.markHistoryStale()
        owner.readSignalWindowSerial = owner.serial
    }

    /**
     * 합치기 창이 닫혔다 — Swift `closeMessageActivityWindow(pendingSerial:)`(748-761). 창에 모인 계기를 **그보다 나중에 띄운** 조회가
     * 이미 맡았으면 다시 묻지 않는다(창이 열린 사이 플라이아웃을 열어 요약·이력을 받았으면 그게 답이다). 안 맡았으면 [requestActivityRefresh] 한 번.
     * [readSignalArrived] 없이 불리면 지금 순간을 계기로 본다(창 앞 조회는 계기를 맡지 못한다 — 곧 새로고침 한 번).
     */
    fun readSignalWindowClosed(): Job? {
        if (!isSignedIn) return null
        val owner = runtime
        val pendingSerial = owner.readSignalWindowSerial ?: owner.serial
        owner.readSignalWindowSerial = null
        val screenVisible = isMessagesScreenVisible
        val historyTaken = owner.lastHistoryLaunchSerial > pendingSerial
        val summaryTaken = owner.lastSummaryLaunchSerial > pendingSerial
        // 볼 사람이 없는 이력은 낡음으로 적는다(창이 열린 사이 화면이 닫혔을 수 있다 — 다시 설 때 받는다).
        if (!screenVisible && !historyTaken) owner.markHistoryStale()
        // 안 보이는 화면의 이력은 위 낡음 표시가 맡는다. 보이는 화면은 창 뒤에 띄운 이력이 있어야 맡은 것이다.
        val historyCovered = historyTaken || !screenVisible
        if (summaryTaken && historyCovered) return null
        return requestActivityRefresh()
    }

    // ---------------------------------------------------------------- 내부

    /** 메시지 화면(목록 또는 대화)이 지금 보이는가. */
    private val isMessagesScreenVisible: Boolean get() = isAppActive && (isListVisible || openConversationPeerID != null)

    private fun syncRouterVisibility() {
        val link = router ?: return
        val visible = if (isAppActive) openConversationPeerID else null
        if (link.visibleConversationPeerID != visible) link.visibleConversationPeerID = visible
    }

    // ---------------------------------------------------------------- 시험 창구

    val pendingActivityTask: Job? get() = runtime.activityTask
    val pendingPostMarkTask: Job? get() = runtime.postMarkWindowTask
    val isMarkingRead: Boolean get() = runtime.markInFlight.isNotEmpty()
    val isHistoryStale: Boolean get() = runtime.historyStale
    /** 즉시 삽입 장부(메시지 · 찌르기)에 남은 줄 수 — 서버가 답하면 0 으로 돌아온다(Swift `localArrivalSerials.isEmpty`). */
    val pendingLocalArrivalCount: Int get() = runtime.localArrivalSerials.size
    val pendingLocalPokeArrivalCount: Int get() = runtime.pokeLocalArrivalSerials.size

    companion object {
        /**
         * 소비한 메시지 행 → 대화 한 줄(순수, Swift `consumedMessageEntries`). 옮김 규칙은 이력 행과 같다(본문 정규화 · 보이는 글자 없음 버림 ·
         * 빈 id · 보낸이 없음 버림 · 이름 폴백). 받은 말이므로 `isUnread` 는 서버가 읽음을 알면 true, 모르면 null(옛 서버 — 도장 규칙).
         */
        fun consumedMessageEntries(rows: List<TakenPokeRow>, receiptsKnown: Boolean): List<MessageEntry> = rows.mapNotNull { row ->
            if (PokeKind.of(row.kind) != PokeKind.message || row.id.isEmpty() || row.fromUser.isEmpty()) return@mapNotNull null
            val body = MessageBody.sanitized(row.body ?: "")
            if (!MessageBody.hasVisibleContent(body)) return@mapNotNull null
            MessageEntry(
                MessageHistoryEntry(
                    id = row.id,
                    peerUserID = row.fromUser,
                    peerName = row.fromDisplayName.ifEmpty { "사용자" },
                    peerAvatarURL = SwiftURL.parse(row.fromAvatarUrl),
                    body = body,
                    createdAt = SwiftDate(row.createdEpoch.toDouble()),
                    isMine = false,
                    readByPeer = null,
                    isUnread = if (receiptsKnown) true else null,
                ),
            )
        }

        /** "이 서버에는 그 함수가 없다"(맥 `isMissingMessageReadFunction` 과 같은 판정). 401/403·5xx·네트워크는 넣지 않는다. */
        fun isMissingFunction(error: SupabaseWorkServiceError): Boolean = when (error) {
            SupabaseWorkServiceError.DatabaseSchemaMissing -> true
            is SupabaseWorkServiceError.InvalidResponse -> error.statusCode == 404
            else -> false
        }
    }
}

/** 비관찰 장부. 로그아웃이 통째로 새것으로 바꾼다(옛 작업이 새 장부를 만지지 않게 — 세대 가드와 함께). */
private class MessagesRuntime {
    var serial: Int = 0
        private set
    var lastAppliedHistorySerial = 0
    var lastHistoryLaunchSerial = 0
    var lastSummaryLaunchSerial = 0
    var historyInFlight = 0
    var activityTask: Job? = null
    var activityAgain = false
    var activityWantsHistory = false

    /** 이력을 건너뛴 계기의 순간(그보다 나중에 띄운 이력이 반영되면 내린다). null = 낡지 않음. */
    var historyStaleSerial: Int? = null

    /** 데스크톱 읽음 신호 창의 계기 번호(공용 패치 8 — Swift `activityWindowSerial`). null = 창에 얹힌 신호 없음. */
    var readSignalWindowSerial: Int? = null

    /** 활성 새로고침 스로틀(공용 패치 9): 마지막으로 띄운 순간 · 스로틀을 이미 우회한 낡음 표시(같은 표시로는 한 번만 — Swift R3). */
    var lastActiveRefreshAt: SwiftDate? = null
    var activeBypassStaleSerial: Int? = null
    var lastListRefreshAt: SwiftDate = MessagesThreadListRules.distantPast
    var lastDirectoryLoadAt: SwiftDate = MessagesThreadListRules.distantPast
    val markInFlight: MutableSet<String> = LinkedHashSet()
    val markAgain: MutableSet<String> = LinkedHashSet()
    var postMarkWindowTask: Job? = null
    var postMarkPendingSerial = 0
    val shownConversations: MutableList<Pair<String, String>> = ArrayList()

    var historyStale: Boolean
        get() = historyStaleSerial != null
        set(value) {
            historyStaleSerial = if (value) serial else null
        }

    fun nextSerial(): Int {
        serial += 1
        return serial
    }

    /** Swift `markHistoryStale()` — 지금까지의 번호로 적는다(이보다 나중에 띄운 이력만 지운다). */
    fun markHistoryStale() {
        historyStaleSerial = serial
    }

    /**
     * 보이는 대화에 **즉시 삽입한** 도착분(맥 v0.3.31 M4): 메시지 id → 넣은 순간의 일련번호(한 줄에 하나 — take_pokes 행 순서대로 커진다).
     * 그보다 먼저 띄운 이력 응답은 그 말을 모를 수 있으므로 남기고, 나중에 띄운 응답이 오면 서버가 이긴다. 같은 초 도착 순서표이기도 하다.
     */
    val localArrivalSerials: MutableMap<String, Int> = LinkedHashMap()

    /** 기록에 **즉시 넣은** 찌르기(v0.3.65 — take_pokes 소비분). 위 표와 같은 규칙이다. */
    val pokeLocalArrivalSerials: MutableMap<String, Int> = LinkedHashMap()

    /**
     * 일련번호 [historySerial] 로 띄운 이력 응답([server])을 반영할 때 **남겨야 할 즉시 삽입분**을 고르고 장부를 정리한다(Swift
     * `survivingLocalArrivals`): 응답에 같은 id 가 있거나 응답이 삽입보다 나중에 띄운 것이면 장부에서 빼고, 먼저 띄운 것이면 지금 줄을 남긴다.
     */
    fun survivingLocalArrivals(historySerial: Int, current: List<MessageEntry>, server: List<MessageEntry>): List<MessageEntry> =
        surviving(localArrivalSerials, historySerial, current, server.mapTo(HashSet()) { it.id }) { it.id }

    /** [survivingLocalArrivals] 의 찌르기 짝(규칙은 글자 그대로 같다 — 타입만 다르다). */
    fun survivingLocalPokeArrivals(
        historySerial: Int,
        current: List<MessagePokeLogEntry>,
        server: List<MessagePokeLogEntry>,
    ): List<MessagePokeLogEntry> =
        surviving(pokeLocalArrivalSerials, historySerial, current, server.mapTo(HashSet()) { it.id }) { it.id }

    private inline fun <T> surviving(
        ledger: MutableMap<String, Int>,
        historySerial: Int,
        current: List<T>,
        serverIDs: Set<String>,
        id: (T) -> String,
    ): List<T> {
        if (ledger.isEmpty()) return emptyList()
        val keepIDs = HashSet<String>()
        val iterator = ledger.entries.iterator()
        while (iterator.hasNext()) {
            val (entryID, inserted) = iterator.next()
            if (entryID in serverIDs || historySerial > inserted) iterator.remove() else keepIDs += entryID
        }
        if (keepIDs.isEmpty()) return emptyList()
        val seen = HashSet<String>()
        return current.filter { keepIDs.contains(id(it)) && seen.add(id(it)) }
    }

    fun cancelAll() {
        activityTask?.cancel()
        activityTask = null
        postMarkWindowTask?.cancel()
        postMarkWindowTask = null
    }
}
