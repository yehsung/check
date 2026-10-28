// 원본: Sources/CheckMobileKit/Now/NowStorePhoneWork.swift · Sources/CheckMobileKit/Now/NowStore.swift:60-68·179·216·265-276(생존 신호 칸 · 부르는 자리) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.work

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.net.startPhoneWork
import com.yehsung.aingcheck.core.net.stopPhoneWork
import com.yehsung.aingcheck.core.net.touchPhoneWork
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.stores.now.NowFormat
import com.yehsung.aingcheck.core.stores.now.NowPhoneSession
import com.yehsung.aingcheck.core.stores.now.NowPhoneWorkLink
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.PhoneWorkOutcome
import com.yehsung.aingcheck.core.wire.models.PhoneWorkResponse
import com.yehsung.aingcheck.core.wire.models.PhoneWorkSessionInfo
import com.yehsung.aingcheck.core.wire.models.PhoneWorkWallet
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.feature.phone.app.rethrowIfOwnCancellation
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 지금 탭의 근무 시작 · 종료 · 생존 신호(0.3.51 / iOS 1.0.7 — 서버 `20261014130000_phone_work.sql`). W2-b [NowStore] 의 값 칸(버튼 표시 ·
 * 출처 · 안내)에 붙는 **왕복** 몫이다(Swift 는 같은 클래스의 확장 — 여기서는 [NowPhoneWorkLink] 문으로 잇는다).
 *
 * 사장님 결정(2026-10-14): 지금 탭 맨 위 버튼으로 폰이 근무를 시작·종료한다(위젯 버튼 없음). 폰을 잠가도 근무는 이어지고, 마지막 앱 활동에서
 * 2시간 30분이 지나면 확인 알림 한 번 → 10분 유예 → 안 열면 마지막 신호 시각으로 서버가 끝낸다. **판정은 전부 서버가 한다** — 폰은 버튼 둘과
 * '앱을 열었다'는 신호 하나만 보낸다.
 *
 * 규칙
 * - **본문에 시각을 싣지 않는다**(서버 now() — C§4 #12, G §2-3 W2-f ①). 시작·생존 신호는 `{}`, 종료는 보던 세션 id 하나(없으면 `{}`).
 *   실패하면 큐에 넣지 않고 안내만 한다 — 클라 시각으로 재시도하면 근무 시간 위조(P0)가 열린다.
 * - 함수가 없는 서버(404 PGRST202)는 이 세대 동안 [NowStore.phoneWorkAvailable] = false — 버튼을 숨긴다(앱이 db push 보다 먼저 나간 창, E§5.3).
 * - 세대 가드: 왕복 중 로그아웃·계정 전환이 있었으면 응답을 버린다.
 * - 시작·종료 뒤에는 팀 상태를 다시 읽고 위젯을 스로틀 없이 바로 새로고침한다([reloadWidgets]).
 *
 * @param ruby 루비 미러(지갑 정산 결과 — 3시간 랩이 방금 지급됐을 수 있다. 오목·체스·테트리스·상점과 **한 칸**).
 * @param weeklyWorkDidChange 근무가 막 닫혔다 — 나 탭 주간 보상을 스로틀 없이 다시 읽는다(Swift `context.links.me?.weeklyWorkDidChange()`).
 * @param reloadWidgets 위젯 타임라인 즉시 새로고침(Swift `context.session.reloadWidgetTimelines()`).
 */
class PhoneWorkController(
    private val now: NowStore,
    private val ruby: RubyBalanceMirror,
    private val weeklyWorkDidChange: () -> Unit = {},
    private val reloadWidgets: () -> Unit = {},
) : NowPhoneWorkLink {
    private val context get() = now.context
    private val prefs: KeyValueStore get() = context.keyValueStore

    /** 마지막 생존 신호를 보낸 시각(스로틀). */
    var lastPhoneTouchAt: SwiftDate? = null
        private set

    /** 도는 생존 신호(시험이 기다린다). */
    var phoneTouchTask: Job? = null
        private set

    /** 신호가 도는 중에 '반드시 한 번 더'(근무 확인 알림)가 왔다 — 끝나면 바로 다시 보낸다. */
    private var phoneTouchRerun = false

    /** 생존 신호 횟수(시험). */
    var phoneTouchCount: Int = 0
        private set

    // ---------------------------------------------------------------- 화면 값

    /** 버튼 줄을 그릴지(소속이 있고 팀 상태를 받았고 서버에 함수가 있다). */
    val showsWorkControl: Boolean
        get() = now.phoneWorkAvailable && !now.hasNoTeam && !now.isSettlingTeam && now.membership != null && now.hasLoadedTeam

    /** 무소속이라 버튼이 꺼진 자리를 그릴지(서버에 함수가 있을 때만 — 없으면 아예 안 보인다). */
    val showsDisabledWorkControlForNoTeam: Boolean
        get() = now.phoneWorkAvailable && now.hasNoTeam

    /** 지금 근무 중인가(내 팀 상태 행 기준 — 카드와 같은 값). */
    val isMyWorkOpen: Boolean
        get() = now.myStatus?.status == WorkStatus.working

    /** 지금 근무의 출처(버튼 아래 안내 · 종료 확인 문구). */
    val myWorkOrigin: NowWorkOrigin
        get() = now.myStatus?.let(now::workOrigin) ?: NowWorkOrigin.unknown

    fun clearWorkNotice() {
        now.workNotice = null
    }

    // ---------------------------------------------------------------- 시작 · 종료

    /** [근무 시작]. 서버가 세션을 연다(시각 = 서버 now). 이미 열린 근무가 있으면(맥 포함) 새로 열지 않는다. */
    suspend fun clockIn() {
        if (!context.sessionStore.isSignedIn || now.isWorkBusy || !now.phoneWorkAvailable) return
        if (now.membership == null || now.hasNoTeam) {
            now.workNotice = NowText.workNeedsTeam
            return
        }
        now.isWorkBusy = true
        now.workNotice = null
        try {
            val generation = context.generation
            val service = context.service
            val response: PhoneWorkResponse = try {
                context.withSessionRetry { session -> service.startPhoneWork(session.accessToken) }
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (generation != context.generation) return
                now.workNotice = failureNotice(error, NowText.startFailed)
                return
            }
            if (generation != context.generation) return
            applyPhoneWallet(response.wallet)
            when (val outcome = PhoneWorkOutcome.from(response)) {
                is PhoneWorkOutcome.Working -> {
                    phoneSession(outcome.session, response)?.let { now.phoneSession = it }
                    lastPhoneTouchAt = context.clock.now()
                    now.workNotice = if (outcome.alreadyWorking) {
                        if (outcome.session.origin == NowWorkOrigin.mac.rawValue) NowText.alreadyWorkingOnMac else NowText.alreadyWorking
                    } else {
                        NowText.workStarted
                    }
                }
                PhoneWorkOutcome.NoTeam -> now.workNotice = NowText.workNeedsTeam
                else -> now.workNotice = NowText.startFailed
            }
            // Swift `defer { isWorkBusy = false }` 는 함수 끝에서 돈다 — 새로고침이 끝날 때까지 버튼이 잠겨 있다.
            refreshAfterWorkChange()
        } finally {
            now.isWorkBusy = false
        }
    }

    /**
     * [근무 종료](확인 뒤). **내 열린 근무**를 서버가 닫는다 — 맥이 연 근무도(사람당 하나). 보던 세션 id 를 실어 그 사이 바뀐 세션(맥이 닫고
     * 새로 열었다)은 닫지 않는다(mismatch).
     */
    suspend fun clockOut() {
        if (!context.sessionStore.isSignedIn || now.isWorkBusy || !now.phoneWorkAvailable) return
        now.isWorkBusy = true
        now.workNotice = null
        try {
            val generation = context.generation
            val service = context.service
            val me = now.myStatus
            val sessionID = (me?.openSession?.id ?: me?.activeSessionID ?: now.phoneSession?.id)?.lowercase()
            val response: PhoneWorkResponse = try {
                context.withSessionRetry { session -> service.stopPhoneWork(session.accessToken, sessionID) }
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (generation != context.generation) return
                now.workNotice = failureNotice(error, NowText.stopFailed)
                return
            }
            if (generation != context.generation) return
            applyPhoneWallet(response.wallet)
            when (PhoneWorkOutcome.from(response)) {
                is PhoneWorkOutcome.Stopped -> {
                    now.phoneSession = null
                    now.workNotice = NowText.workStopped
                    // 근무가 막 닫혔다 — 이번 주 누적이 확정됐으니 주간 보상을 스로틀 없이 다시 읽는다(나 탭 카드 · 루비 미러).
                    weeklyWorkDidChange()
                }
                is PhoneWorkOutcome.NotWorking -> {
                    now.phoneSession = null
                    now.workNotice = NowText.alreadyStopped
                    weeklyWorkDidChange()
                }
                PhoneWorkOutcome.Mismatch -> now.workNotice = NowText.workChanged
                else -> now.workNotice = NowText.stopFailed
            }
            refreshAfterWorkChange()
        } finally {
            now.isWorkBusy = false
        }
    }

    // ---------------------------------------------------------------- 생존 신호(NowPhoneWorkLink)

    /** 앱이 앞으로 왔다 — 1분 스로틀(앱 전환이 잦아도 1분에 한 번이면 2시간 30분 판정에 충분하다). */
    override fun appDidBecomeActive() {
        touchPhoneWorkIfNeeded(PHONE_TOUCH_ON_ACTIVE_SECONDS)
    }

    /** active 동안 60초 주기 — 폰이 연 근무일 때만 지금 탭이 부른다. 5분 스로틀. */
    override fun periodicTick() {
        touchPhoneWorkIfNeeded(PHONE_TOUCH_WHILE_ACTIVE_SECONDS)
    }

    /** 로그아웃 — 왕복 몫만 비운다(값 칸은 지금 탭이 비운다). */
    override fun reset() {
        phoneTouchTask?.cancel()
        phoneTouchTask = null
        phoneTouchRerun = false
        lastPhoneTouchAt = null
    }

    /**
     * 앱 활동 신호를 보낸다(스로틀). 도는 중이면 겹쳐 보내지 않는다([force] 면 끝난 뒤 한 번 더). 함수가 없는 서버면 아무것도 안 한다.
     */
    fun touchPhoneWorkIfNeeded(minimumInterval: Double, force: Boolean = false) {
        if (!now.phoneWorkAvailable || !context.sessionStore.isSignedIn) return
        if (phoneTouchTask != null) {
            if (force) phoneTouchRerun = true
            return
        }
        val at = context.clock.now()
        val last = lastPhoneTouchAt
        if (last != null) {
            val age = at.timeIntervalSince(last)
            if (age >= 0 && age < minimumInterval) return
        }
        lastPhoneTouchAt = at
        val generation = context.generation
        val job = now.scope.launch(start = CoroutineStart.LAZY) {
            performPhoneTouch(generation)
            phoneTouchTask = null
            if (phoneTouchRerun && generation == context.generation) {
                phoneTouchRerun = false
                lastPhoneTouchAt = null
                touchPhoneWorkIfNeeded(0.0)
            }
        }
        phoneTouchTask = job
        job.start()
    }

    /**
     * 근무 확인 알림을 받았다(앱이 앞에 있거나 알림을 눌러 열었다) — 스로틀 없이 바로 신호를 보내고 카드를 새로 읽는다
     * (Swift `PushWorkCheckRefreshing.didReceiveWorkCheckPush` — 앱을 연 것 자체가 '아직 근무 중'이라는 답이다).
     */
    fun didReceiveWorkCheckPush() {
        if (!context.sessionStore.isSignedIn) return
        lastPhoneTouchAt = null
        touchPhoneWorkIfNeeded(0.0, force = true)
        now.refresh()
    }

    private suspend fun performPhoneTouch(generation: Int) {
        val service = context.service
        phoneTouchCount += 1
        val response: PhoneWorkResponse = try {
            context.withSessionRetry { session -> service.touchPhoneWork(session.accessToken) }
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (generation != context.generation) return
            if (isMissingDeviceFunction(error)) {
                now.phoneWorkAvailable = false
                now.phoneSession = null
            } else {
                // 닿지 못했다 — 다음 활성화가 바로 다시 보내게 스로틀을 푼다(서버 판정은 마지막으로 닿은 신호 기준).
                lastPhoneTouchAt = null
            }
            return
        }
        if (generation != context.generation) return
        applyPhoneWallet(response.wallet)
        when (val outcome = PhoneWorkOutcome.from(response)) {
            is PhoneWorkOutcome.Working -> {
                val next = phoneSession(outcome.session, response) ?: return
                val me = now.myStatus
                val known = (me?.openSession?.id ?: me?.activeSessionID)?.lowercase()
                now.phoneSession = next
                // 카드가 모르는 근무다(다른 기기가 방금 열었다) — 다시 읽는다.
                if (known != next.id) now.refresh()
            }
            is PhoneWorkOutcome.NotWorking -> {
                val cardSaysWorking = isMyWorkOpen
                now.phoneSession = null
                val last = outcome.last
                val id = last?.id?.lowercase()
                if (last != null && last.reason == "idle" && id != null && !hasAcknowledgedIdleClose(id)) {
                    acknowledgeIdleClose(id)
                    val ended = last.endedAt?.let(::parseServerDate)?.let(NowFormat::clockTime)
                    now.workNotice = NowText.idleClosed(ended)
                }
                if (cardSaysWorking) now.refresh()
            }
            else -> Unit
        }
    }

    // ---------------------------------------------------------------- 내부

    /**
     * 시작·종료 뒤: 카드·위젯 스냅숏을 서버 값으로 다시 쓰고, 위젯은 스로틀 없이 바로 새로고침한다(위젯 버튼은 없다 — 앱에서 누른 결과가
     * 홈 화면에 30초 늦게 뜨지 않게).
     */
    private suspend fun refreshAfterWorkChange() {
        if (!context.sessionStore.isSignedIn) return
        now.refresh()
        now.refreshTask?.join()
        if (!context.sessionStore.isSignedIn) return
        reloadWidgets()
    }

    private fun failureNotice(error: Throwable, fallback: String): String? {
        if (isMissingDeviceFunction(error)) {
            now.phoneWorkAvailable = false
            now.phoneSession = null
            return NowText.workUnavailable
        }
        if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return null
        return if (AuthErrorRules.isTransport(error)) SessionText.network else AuthErrorRules.message(error, fallback)
    }

    /** 지갑 정산 결과의 루비 잔액을 미러에 싣는다(3시간 랩이 방금 지급됐을 수 있다 — 상점·게임 탭이 같은 값을 본다). */
    private fun applyPhoneWallet(wallet: PhoneWorkWallet?) {
        val balance = wallet?.rubyBalance ?: return
        ruby.rubyBalance = balance
    }

    /** "자리비움으로 끝났어요" 안내는 세션마다 한 번(계정별 키 — 같은 폰에서 계정을 바꿔도 앞 사람 것을 물려받지 않게). */
    private val idleCloseAckKey: String?
        get() = context.sessionStore.userID?.let { "$IDLE_ACK_PREFIX$it" }

    private fun hasAcknowledgedIdleClose(id: String): Boolean {
        val key = idleCloseAckKey ?: return true
        return prefs.getString(key) == id
    }

    private fun acknowledgeIdleClose(id: String) {
        val key = idleCloseAckKey ?: return
        prefs.putString(key, id)
    }

    companion object {
        /** 앱이 active 가 될 때 생존 신호 최소 간격(초). */
        const val PHONE_TOUCH_ON_ACTIVE_SECONDS: Double = 60.0

        /** 앱을 켜 둔 채(active 유지) 보내는 생존 신호 간격(초). */
        const val PHONE_TOUCH_WHILE_ACTIVE_SECONDS: Double = 300.0

        /** 계정별 '자리비움 마감 안내를 이미 보였다' 키 머리(Swift `aing.now.phoneWorkIdleAck.<uid>`). */
        const val IDLE_ACK_PREFIX: String = "aing.now.phoneWorkIdleAck."

        /** 응답 세션 → 내 열린 세션 값. id 가 없으면 null. 모르는 origin 은 **mac** 으로 접는다(옛 iOS 와 같은 규칙 — §8-1, §8-7 W2-f). */
        fun phoneSession(info: PhoneWorkSessionInfo, response: PhoneWorkResponse): NowPhoneSession? {
            val id = info.id?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
            return NowPhoneSession(
                id = id,
                origin = originOf(info.origin),
                checkAt = response.checkAt?.let(::parseServerDate),
                checkAfterSeconds = response.checkAfterSeconds?.let { it.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt() },
            )
        }

        /**
         * 서버 origin 글자 → 출처. `phone` 만 폰이고 나머지(`mac` · **`windows`** · 모르는 값 · 없음)는 전부 **mac** 이다 — 이 폰이 연 근무가 아니라는
         * 뜻("맥에서 연 근무예요 · 여기서 끝낼 수도 있어요")이다. 새 출처를 만들지 않는다(§8-1 D:675 · §8-7 W2-f: Windows 가 `'windows'` 를 실어도
         * 옛 iOS 가 `.mac` 으로 접는 것과 같은 판정).
         */
        fun originOf(raw: String?): NowWorkOrigin = when (raw) {
            NowWorkOrigin.phone.rawValue -> NowWorkOrigin.phone
            else -> NowWorkOrigin.mac
        }

        /** 서버 timestamptz 글자(소수초 있음·없음 둘 다 — Swift `parseServerDate`). */
        fun parseServerDate(value: String): SwiftDate? = SwiftISO8601.parse(value)
    }
}
