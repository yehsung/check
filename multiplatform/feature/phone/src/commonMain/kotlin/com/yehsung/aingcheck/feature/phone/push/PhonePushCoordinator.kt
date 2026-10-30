// 원본: Sources/CheckMobileKit/Push/PushCoordinator.swift · Sources/CheckMobileKit/Push/PushNotificationSystem.swift:38-66(받는 문 셋) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.push

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.net.fetchMessageUnreadSummary
import com.yehsung.aingcheck.core.session.DeviceRegistrationReason
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.didReceiveFeedbackReplyPush
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.feature.phone.app.PhoneContext
import com.yehsung.aingcheck.feature.phone.app.rethrowIfOwnCancellation
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 푸시 받기(SPEC-ios §5 · SPEC-ios-build D9 · E§6). 시스템 일은 [PhonePushSystem](Android: FCM · NotificationManager · 권한 창 — 조립이 단다)에
 * 시키고, 판단은 여기서 해서 JVM 시험으로 잰다(Swift 와 같은 구조).
 *
 * 자리 API(앱 모델이 부르는 것): [appDidBecomeActive] · [appDidEnterBackground] · [reset] · [sessionDidSignIn] — 탭 스토어와 같은 수명 규칙.
 * 시스템이 부르는 것: [didReceivePushToken] · [didFailToRegister] · [didReceive] · [handleResponse].
 *
 * 하는 일
 * 1. **권한**: 로그인 뒤 앱이 앞에 있고 권한을 아직 묻지 않았으면(Android 13+) 설명 시트를 먼저 띄운다("나중에"는 7일 쉰다). 폼 로그인 직후면
 *    자동 채우기 저장 창이 뜰 수 있는 유예(3초 — E§6.5 iOS 선례) 뒤에 띄운다. 실행 복원 · 앞으로 돌아옴은 곧바로다.
 * 2. **토큰 등록**(G §2-3 W2-f ④): 받을 수 있으면 실행마다 한 번 FCM 토큰을 받아 세션 스토어에 넘긴다 → `register_device_fcm` **하나**
 *    (W2-a K5 — `register_device` 를 따로 부르지 않는다). **받을 수 없으면**(권한 꺼짐) 토큰 없이 넘긴다 → 세션이 `unregister_device` 뒤 토큰
 *    없이 다시 등록한다(K5: 토큰을 빼고 보내면 서버가 옛 토큰을 **유지**하므로 그것만으로는 푸시가 멈추지 않는다 — §8-1 대체 표).
 * 3. **도착**([didReceive]): 해당 스토어를 새로고침하고, 지금 보고 있는 대화의 메시지 · 앱이 앞일 때의 근무 확인이면 숨김으로 답한다.
 * 4. **응답**([handleResponse]): 탭 → 라우트 · 수락 → 오목/체스 respond(accept) 후 대국 열기. 실행 복원이 끝날 때까지 기다린다. 화면을 여는 길은
 *    전부 딥링크 대상 해석([PhoneContext.openRoute] — 탭 스토어 규칙)이다. 라우터를 바로 부르지 않는다(소스 계약 시험이 잰다).
 * 5. **앱 배지** = 메시지 안 읽은 수 + 받은 오목 신청 수. **모르면 적지 않는다**(push-verify 발견 2).
 * 6. **알림 설정 공개 API**(나 탭 설정 화면): [authorization] · [prefs] · [knowsPrefs] · [isEnabled] · [isSavingPrefs] · [prefsNotice] ·
 *    [setPreference] · [enableNotifications] · [refreshAuthorization] · [openSystemSettings]. 저장은 직렬이다.
 *
 * 서버가 준비 안 된 응답(G §2-3 W2-f ⑤ — `invalid` · PGRST202 · `unknown_platform`)은 화면 경고 없이 접는다: 기기 등록은 세션 스토어가 조용히
 * 접고(다음 포그라운드가 다시), 배지 확인의 PGRST202 는 '답했다'로 접는다(메시지 탭이 옛 이력 규칙으로 접는 것과 같다).
 *
 * 폰 금지 호출 없음: 이 자리가 부르는 서버 함수는 message_unread_summary(배지 확인) · gomoku/chess respond(수락 — 스토어 경유) ·
 * register_device_fcm · unregister_device · set_push_prefs(세션 경유)뿐이다.
 */
class PhonePushCoordinator(
    private val context: PhoneContext,
    /** 데모 조립인가(스크린숏이 시트에 가리지 않게 — 데모에서는 설명 시트를 띄우지 않는다). */
    private val isDemo: Boolean = false,
) {
    var system: PhonePushSystem? = null
        private set

    private val session get() = context.sessionStore

    // ---------------------------------------------------------------- 관찰 상태(나 탭 · 설명 시트가 읽는다)

    /** 시스템 알림 권한(마지막으로 읽은 값). */
    var authorization: PhonePushAuthorization by mutableStateOf(PhonePushAuthorization.unknown)
        private set

    /** 설명 시트가 떠 있는가. */
    var isPrimerPresented: Boolean by mutableStateOf(false)
        private set

    /** 시스템 권한 창을 기다리는 중(버튼 잠금). */
    var isRequestingAuthorization: Boolean by mutableStateOf(false)
        private set

    /** 알림 설정을 저장하는 중. 저장 중에는 [prefs] 가 누른 값을 먼저 보여 준다. */
    var isSavingPrefs: Boolean by mutableStateOf(false)
        private set

    /** 알림 설정 저장 실패 한 줄. */
    var prefsNotice: String? by mutableStateOf(null)

    // ---------------------------------------------------------------- 설정값

    /** 알림으로 켜진 앱이 실행 복원을 기다리는 상한(초). */
    var sessionSettleTimeoutSeconds: Double = 10.0

    /** 다른 오목·체스 요청이 끝나기를 기다리는 상한(초). */
    var gameBusyTimeoutSeconds: Double = 3.0

    /** 폼 로그인 직후 자동 채우기 저장 창이 **뜨기를** 기다리는 유예(초). */
    var credentialPromptGraceSeconds: Double = 3.0

    /** 유예를 재는 잠(취소되면 곧바로 돌아온다). 시험은 문으로 바꾼다. */
    var credentialPromptGraceSleep: suspend (Double) -> Unit = { seconds -> delay((seconds * 1000.0).toLong()) }

    // ---------------------------------------------------------------- 내부

    private var isAppActive = false
    private var registeredThisLaunch = false
    private var statusTask: Job? = null
    private var statusCheckAgain = false
    private var statusCheckWantsPrimer = false

    /** 이번 로그인이 폼 제출로 시작됐고 아직 설명 시트 판정을 끝내지 않았다. 실행 복원 · 앞으로 돌아옴에는 서지 않는다. */
    private var awaitsCredentialPrompt = false
    private var primerDeferral: PrimerDeferral? = null
    private var credentialGraceTask: Job? = null

    /** 유예 표지. 취소 · 새 유예마다 올린다 — 늦게 끝난 잠이 지금 상태를 건드리지 않게. */
    private var credentialGraceToken = 0
    private var isObservingSystemOverlay = false

    /** 사용자가 마지막으로 누른 알림 설정(저장이 끝날 때까지 화면이 이 값을 그린다). */
    private var desiredPrefs: PushPrefs? by mutableStateOf(null)
    private var prefsSaveTask: Deferred<Boolean>? = null
    private var prefsSaveAgain = false

    /** 앱 배지의 앎(관찰한다 — 바뀌면 배지 관찰이 다시 계산한다). */
    private var badgeKnowledge: BadgeKnowledge by mutableStateOf(BadgeKnowledge.unknown)
    private var badgeTrackingJob: Job? = null
    private var badgeConfirmTask: Job? = null
    private var badgeConfirmAgain = false

    /** 마지막으로 적은 아이콘 숫자(시험·진단). */
    var lastAppliedBadge: Int? = null
        private set

    /** 마지막 토큰 받기 실패(진단). 토큰 원문·오류의 망 주소를 싣지 않는다 — 종류 이름만. */
    var lastRegistrationError: String? = null
        private set

    /** 앱 배지 합의 출처(기본: 메시지 · 게임 탭 배지 합). 스냅숏 상태를 읽어야 한다 — 바뀌면 다시 적는다. 시험이 바꾼다. */
    var badgeTotalSource: () -> Int = { context.links.badges.appBadgeTotal }

    /** 앱 배지를 얼마나 아는가. */
    enum class BadgeKnowledge {
        /** 이번 세대에 서버 값을 아직 모른다 — 아이콘을 건드리지 않는다(앞 실행이 적은 값을 둔다). */
        unknown,

        /** 앱이 앞에서 서버 확인을 마쳤다 — 탭 배지 합을 관찰해 적는다. */
        stores,
    }

    /** 설명 시트를 미룬 이유. */
    enum class PrimerDeferral {
        /** 폼 로그인 직후 — 자동 채우기 저장 창이 뜰 수 있는 유예 중. */
        credentialPromptGrace,

        /** 우리가 띄우지 않은 시스템 화면이 앱 위에 있다 — 사라지면 다시 판정한다. */
        systemOverlay,
    }

    val badgeState: BadgeKnowledge get() = badgeKnowledge
    val primerDeferralState: PrimerDeferral? get() = primerDeferral
    val pendingCredentialPromptGrace: Job? get() = credentialGraceTask
    val isObservingSystemOverlayState: Boolean get() = isObservingSystemOverlay

    /** 진행 중 확인(시험이 기다린다). */
    val pendingStatusCheck: Job? get() = statusTask

    /** 진행 중인 배지 확인(시험이 기다린다). */
    val pendingBadgeConfirmation: Job? get() = badgeConfirmTask

    /** 시스템 어댑터를 붙인다(조립 — Application/Activity 준비 뒤 한 번). 배지 관찰만 건다 — 실행 복원 중에는 모르는 값이라 적지 않는다. */
    fun attach(system: PhonePushSystem) {
        this.system = system
        startBadgeTracking()
    }

    // ---------------------------------------------------------------- 수명

    fun appDidBecomeActive() {
        isAppActive = true
        startBadgeTracking()
        if (badgeKnowledge == BadgeKnowledge.stores) {
            applyBadge()
        } else {
            // 탭 스토어가 방금 새로고침을 띄웠다. 서버가 한 번 답한 뒤부터 합을 적는다(오프라인이면 앞 실행 값을 둔다).
            confirmBadge()
        }
        updateSystemOverlayObservation()
        requestStatusCheck(allowPrimer = true)
    }

    fun appDidEnterBackground() {
        isAppActive = false
        cancelCredentialGrace()
        awaitsCredentialPrompt = false
        primerDeferral = null
        updateSystemOverlayObservation()
    }

    /**
     * 로그아웃 · 치명 만료(세대가 바뀐 직후). 설명 시트를 내리고 배지를 0 으로, 알림 창의 이 앱 알림을 지운다(앞 계정의 보낸 사람·본문이
     * 다음 계정의 폰에 남지 않게). FCM 토큰을 버리고 저장된 토큰을 잊는다 — 치명 만료는 서버에 알릴 토큰이 없어 기기 행이 남고 로그아웃 정리도
     * 실패할 수 있다. 버린 토큰은 FCM 이 UNREGISTERED 로 거절해 서버 발송기가 비운다. 다음 로그인에서 권한이 있으면 다시 받는다.
     */
    fun reset() {
        statusTask?.cancel()
        statusTask = null
        statusCheckAgain = false
        statusCheckWantsPrimer = false
        cancelCredentialGrace()
        awaitsCredentialPrompt = false
        primerDeferral = null
        if (isPrimerPresented) {
            isPrimerPresented = false
            system?.dismissPermissionPrimer()
        }
        updateSystemOverlayObservation()
        isRequestingAuthorization = false
        desiredPrefs = null
        prefsSaveTask = null
        prefsSaveAgain = false
        isSavingPrefs = false
        prefsNotice = null
        badgeConfirmTask?.cancel()
        badgeConfirmTask = null
        badgeConfirmAgain = false
        badgeKnowledge = BadgeKnowledge.unknown
        // 로그아웃의 0 은 확정값이다(다음 계정 값을 모르는 채 앞 계정 숫자를 남기지 않는다).
        apply(0)
        system?.let {
            it.removeAllDeliveredNotifications()
            it.unregisterForRemoteNotifications()
        }
        registeredThisLaunch = false
        session.updatePushToken(null)
    }

    fun sessionDidSignIn() {
        startBadgeTracking()
        // 폼으로 들어왔으면(실행 복원이 아니면) 이번 로그인의 첫 설명 시트 판정은 자동 채우기 저장 창을 먼저 기다린다.
        awaitsCredentialPrompt = session.signedInViaForm
        // 앱이 앞에 있으면 앱 모델이 곧바로 appDidBecomeActive 를 부른다(설명 시트는 그쪽에서) — 여기서는 등록만.
        requestStatusCheck(allowPrimer = false)
    }

    /**
     * 새 FCM 토큰(토큰 받기 결과 · `onNewToken`). **받을 수 있을 때만** 세션에 넘긴다 — 권한이 꺼진 동안 회전된 토큰을 올리면 보이지 않을 푸시가
     * 앱을 깨운다. 토큰 원문을 로그에 싣지 않는다.
     */
    fun didReceivePushToken(token: String) {
        lastRegistrationError = null
        if (!authorization.allowsDelivery) return
        session.updatePushToken(token)
    }

    /** 토큰 받기 실패(Firebase 미초기화 빌드 · 오프라인). 조용히 두고 다음 active 때 다시 시도한다. */
    fun didFailToRegister(reason: String) {
        lastRegistrationError = reason
        registeredThisLaunch = false
    }

    // ---------------------------------------------------------------- 권한 · 토큰 등록

    /** 권한을 읽고, 받을 수 있으면 등록, 아직 안 물었으면(허락 시) 설명 시트. 겹치면 뒤따르는 한 번으로 합친다. */
    private fun requestStatusCheck(allowPrimer: Boolean) {
        statusCheckWantsPrimer = statusCheckWantsPrimer || allowPrimer
        if (system == null) return
        if (statusTask != null) {
            statusCheckAgain = true
            return
        }
        val job = context.scope.launch(start = CoroutineStart.LAZY) {
            do {
                statusCheckAgain = false
                val wantsPrimer = statusCheckWantsPrimer
                statusCheckWantsPrimer = false
                performStatusCheck(wantsPrimer)
            } while (statusCheckAgain)
            statusTask = null
        }
        statusTask = job
        job.start()
    }

    private suspend fun performStatusCheck(allowPrimer: Boolean) {
        val system = system ?: return
        if (!session.isSignedIn) return
        val generation = context.generation
        val status = system.authorizationStatus()
        if (generation != context.generation || !session.isSignedIn) return
        if (authorization != status) authorization = status
        if (allowPrimer && shouldPresentPrimer(status)) {
            decidePrimerPresentation()
        } else {
            // 시트가 필요 없다고 판정한 것도 이번 로그인의 판정이다 — 나중(7일 뒤 등)의 판정에 로그인 유예를 끌고 가지 않는다.
            if (allowPrimer) awaitsCredentialPrompt = false
            applyDelivery(status)
        }
    }

    /**
     * 받을 수 있으면 실행마다 한 번 토큰을 받는다. **받을 수 없으면 토큰을 거둔다**(Android: 데이터 메시지는 권한과 무관하게 도착해 앱을 깨우므로,
     * 권한을 끈 기기에는 서버가 보내지 않게 해야 한다 — 세션이 `unregister_device` 뒤 토큰 없이 다시 등록한다, K5).
     */
    private fun applyDelivery(status: PhonePushAuthorization) {
        if (status.allowsDelivery) {
            registerIfNeeded()
        } else if (status != PhonePushAuthorization.unknown) {
            registeredThisLaunch = false
            session.updatePushToken(null)
        }
    }

    /** 띄울 때라고 판정한 뒤: 시스템 화면이 떠 있으면 사라질 때까지, 폼 로그인 직후면 유예만큼 미룬다. 아니면 곧바로 띄운다. */
    private fun decidePrimerPresentation() {
        val system = system ?: return
        if (system.isSystemOverlayPresented) {
            awaitsCredentialPrompt = false
            cancelCredentialGrace()
            primerDeferral = PrimerDeferral.systemOverlay
        } else if (awaitsCredentialPrompt) {
            primerDeferral = PrimerDeferral.credentialPromptGrace
            startCredentialGraceIfNeeded()
        } else {
            primerDeferral = null
            presentPrimer()
        }
        updateSystemOverlayObservation()
    }

    private fun startCredentialGraceIfNeeded() {
        if (credentialGraceTask != null) return
        credentialGraceToken += 1
        val token = credentialGraceToken
        val generation = context.generation
        val seconds = credentialPromptGraceSeconds
        credentialGraceTask = context.scope.launch {
            credentialPromptGraceSleep(seconds)
            credentialGraceDidEnd(token, generation)
        }
    }

    /** 유예가 창 없이 끝났다 → 다시 판정(그 사이 권한이 바뀌었을 수 있어 권한부터 다시 읽는다). */
    private fun credentialGraceDidEnd(token: Int, generation: Int) {
        if (token != credentialGraceToken) return
        credentialGraceTask = null
        if (generation != context.generation || !session.isSignedIn) return
        awaitsCredentialPrompt = false
        if (primerDeferral != PrimerDeferral.credentialPromptGrace) return
        primerDeferral = null
        updateSystemOverlayObservation()
        if (!isAppActive) return
        requestStatusCheck(allowPrimer = true)
    }

    private fun cancelCredentialGrace() {
        credentialGraceToken += 1
        credentialGraceTask?.cancel()
        credentialGraceTask = null
    }

    /**
     * 어댑터가 부른다(관찰을 켠 동안, 값이 바뀔 때만): 우리가 띄우지 않은 시스템 화면이 떴다(true) · 사라졌다(false).
     * 떴다: 유예를 끝내고, 설명 시트가 이미 떠 있으면 **거둬들인다**(사용자가 고른 것이 아니므로 7일 쉼을 적지 않는다).
     * 사라졌다: 그 화면 때문에 미뤘거나 거둬들인 시트를 다시 판정한다.
     */
    fun systemOverlayDidChange(presented: Boolean) {
        if (!session.isSignedIn) return
        if (presented) {
            awaitsCredentialPrompt = false
            if (primerDeferral == PrimerDeferral.credentialPromptGrace) {
                cancelCredentialGrace()
                primerDeferral = PrimerDeferral.systemOverlay
            }
            if (isPrimerPresented && !isRequestingAuthorization) {
                isPrimerPresented = false
                system?.dismissPermissionPrimer()
                primerDeferral = PrimerDeferral.systemOverlay
            }
        } else if (primerDeferral == PrimerDeferral.systemOverlay) {
            primerDeferral = null
            if (isAppActive) requestStatusCheck(allowPrimer = true)
        }
        updateSystemOverlayObservation()
    }

    /** 관찰은 필요한 동안만: 로그인 · 앱이 앞 · (시트를 미뤘거나 띄워 둔 동안). */
    private fun updateSystemOverlayObservation() {
        val system = system ?: return
        val wanted = isAppActive && session.isSignedIn && (primerDeferral != null || isPrimerPresented)
        if (wanted == isObservingSystemOverlay) return
        isObservingSystemOverlay = wanted
        if (wanted) system.startObservingSystemOverlay { presented -> systemOverlayDidChange(presented) } else system.stopObservingSystemOverlay()
    }

    /** 설명 시트를 띄울 때인가: 로그인 · 앱이 앞 · 권한 미결정 · 시트 없음 · "나중에"에서 7일 지남 · 데모 아님. */
    fun shouldPresentPrimer(status: PhonePushAuthorization): Boolean {
        if (!session.isSignedIn || !isAppActive || isPrimerPresented) return false
        if (isDemo || status != PhonePushAuthorization.notDetermined) return false
        val dismissed = context.keyValueStore.getString(PRIMER_DISMISSED_AT_KEY)?.toDoubleOrNull()
        if (dismissed != null) {
            val elapsed = context.clock.now().timeIntervalSince1970 - dismissed
            // 시계가 뒤로 간 경우(elapsed < 0)도 쉬는 중으로 본다.
            if (elapsed < PRIMER_COOLDOWN_SECONDS) return false
        }
        return true
    }

    private fun presentPrimer() {
        isPrimerPresented = true
        system?.presentPermissionPrimer()
        updateSystemOverlayObservation()
    }

    /** 실행마다 한 번. 결과는 [didReceivePushToken] 으로 온다. */
    private fun registerIfNeeded() {
        val system = system ?: return
        if (registeredThisLaunch) return
        registeredThisLaunch = true
        system.registerForRemoteNotifications()
    }

    /** 설명 시트 "알림 켜기": 시스템 권한 창 → 허락이면 토큰 받기. */
    suspend fun primerAllow() {
        val system = system ?: return
        if (!isPrimerPresented || isRequestingAuthorization) return
        isRequestingAuthorization = true
        val generation = context.generation
        system.requestAuthorization()
        isRequestingAuthorization = false
        if (generation != context.generation) return
        isPrimerPresented = false
        system.dismissPermissionPrimer()
        updateSystemOverlayObservation()
        refreshAuthorization()
    }

    /** 설명 시트 "나중에"(사용자가 누름): 7일 쉰다. 7일 쉼은 사용자가 직접 고른 두 길(이 버튼 · 끌어내림)에서만 적는다. */
    fun primerLater() {
        if (!isPrimerPresented || isRequestingAuthorization) return
        stampPrimerDismissed()
        isPrimerPresented = false
        system?.dismissPermissionPrimer()
        updateSystemOverlayObservation()
    }

    /** 시트가 사용자 제스처로 사라졌다(어댑터가 부른다) — "나중에"와 같다. 권한 창을 기다리는 중이거나 이미 거둬들인 시트면 무시. */
    fun primerDidDisappear() {
        if (!isPrimerPresented || isRequestingAuthorization) return
        stampPrimerDismissed()
        isPrimerPresented = false
        updateSystemOverlayObservation()
    }

    /** 띄울 창이 끝내 없었다. 사용자가 거절한 것이 아니므로 쉬는 기간을 적지 않는다 — 다음 active 에 다시 본다. */
    fun primerCouldNotPresent() {
        isPrimerPresented = false
        updateSystemOverlayObservation()
    }

    private fun stampPrimerDismissed() {
        context.keyValueStore.putString(PRIMER_DISMISSED_AT_KEY, context.clock.now().timeIntervalSince1970.toString())
    }

    // ---------------------------------------------------------------- 알림 설정 공개 API(나 탭)

    /** 지금 보여 줄 종류별 설정. 저장 중이면 마지막으로 누른 값, 아니면 서버가 마지막으로 알려 준 값(모르면 전부 켜짐 — 서버 기본값). */
    val prefs: PushPrefs get() = desiredPrefs ?: session.pushPrefs ?: PushPrefs()

    fun isEnabled(kind: PhonePushKind): Boolean = kind.isEnabled(prefs)

    /**
     * 이 설치의 종류별 설정을 서버에서 받은 적이 있는가. **모르면 토글을 잠그고 [setPreference] 도 보내지 않는다** — set_push_prefs 는 세 칸을
     * 통째로 보내므로, 모르는 칸을 기본값(전부 켜짐)으로 채워 보내면 이 기기에서 꺼 둔 알림을 되살린다.
     */
    val knowsPrefs: Boolean get() = desiredPrefs != null || session.pushPrefs != null

    /** 권한 한 줄. */
    val authorizationText: String
        get() = when (authorization) {
            PhonePushAuthorization.authorized -> PhonePushText.settingsAuthorized
            PhonePushAuthorization.denied -> PhonePushText.settingsDenied
            PhonePushAuthorization.notDetermined -> PhonePushText.settingsNotDetermined
            PhonePushAuthorization.unknown -> PhonePushText.settingsUnknown
        }

    /** 권한 다시 읽기(설정 화면 표시 · 설정에서 돌아왔을 때). 받을 수 있으면 등록, 없으면 토큰을 거둔다. */
    suspend fun refreshAuthorization() {
        val system = system ?: return
        val generation = context.generation
        val status = system.authorizationStatus()
        if (generation != context.generation) return
        if (authorization != status) authorization = status
        if (session.isSignedIn) applyDelivery(status)
    }

    /** "알림 켜기" 버튼: 아직 안 물었으면 시스템 권한 창, 거절돼 있으면 시스템 설정. */
    suspend fun enableNotifications() {
        val system = system ?: return
        if (authorization == PhonePushAuthorization.unknown) refreshAuthorization()
        when (authorization) {
            PhonePushAuthorization.denied -> system.openSystemSettings()
            PhonePushAuthorization.unknown, PhonePushAuthorization.notDetermined -> {
                if (isRequestingAuthorization) return
                isRequestingAuthorization = true
                system.requestAuthorization()
                isRequestingAuthorization = false
                refreshAuthorization()
            }
            PhonePushAuthorization.authorized -> refreshAuthorization()
        }
    }

    fun openSystemSettings() {
        system?.openSystemSettings()
    }

    /**
     * 종류 하나를 켜고 끈다 → set_push_prefs. 이 설치의 기기 행이 아직 없으면(not_found) 등록을 한 번 기다려 다시 저장한다.
     * **저장은 직렬이다**(push-verify 발견 4): 도는 저장이 있으면 누른 값을 쌓아 두고 그 저장이 끝난 뒤 **최신 값으로 한 번 더** 보낸다.
     * [isSavingPrefs] 는 보낼 것이 모두 끝났을 때만 내린다. 돌려주는 값은 마지막 저장의 성공 여부(함께 기다린 호출 모두 같은 값).
     */
    suspend fun setPreference(kind: PhonePushKind, enabled: Boolean): Boolean {
        if (!session.isSignedIn || !knowsPrefs) return false
        desiredPrefs = kind.setting(enabled, prefs)
        if (!isSavingPrefs) isSavingPrefs = true
        prefsNotice = null
        prefsSaveTask?.let { running ->
            prefsSaveAgain = true
            return running.await()
        }
        val generation = context.generation
        val task = context.scope.async(start = CoroutineStart.LAZY) { runPrefsSaves(generation) }
        prefsSaveTask = task
        task.start()
        return task.await()
    }

    private enum class PrefsSaveOutcome { saved, failed, cancelled }

    private suspend fun runPrefsSaves(generation: Int): Boolean {
        var outcome = PrefsSaveOutcome.cancelled
        do {
            prefsSaveAgain = false
            val target = desiredPrefs ?: break
            outcome = savePrefsOnce(target, generation)
            // 세대가 바뀌었으면 reset 이 상태를 이미 비웠다 — 새 세대의 저장을 건드리지 않고 나간다.
            if (generation != context.generation) return false
        } while (prefsSaveAgain)
        prefsSaveTask = null
        desiredPrefs = null
        isSavingPrefs = false
        return when (outcome) {
            PrefsSaveOutcome.saved -> true
            PrefsSaveOutcome.failed -> {
                prefsNotice = PhonePushText.settingsSaveFailed
                false
            }
            PrefsSaveOutcome.cancelled -> false
        }
    }

    private suspend fun savePrefsOnce(target: PushPrefs, generation: Int): PrefsSaveOutcome {
        for (attempt in 0 until 2) {
            try {
                if (session.savePushPrefs(target) != null) return PrefsSaveOutcome.saved
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (generation != context.generation) return PrefsSaveOutcome.cancelled
                return if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) PrefsSaveOutcome.cancelled else PrefsSaveOutcome.failed
            }
            if (generation != context.generation) return PrefsSaveOutcome.cancelled
            if (attempt != 0) break
            // not_found: 기기 행이 없다(첫 등록이 실패했거나 아직 안 끝났다) — 등록을 끝까지 기다린 뒤 한 번 더.
            session.requestDeviceRegistration(DeviceRegistrationReason.signIn)
            session.pendingDeviceRegistration?.join()
            if (generation != context.generation) return PrefsSaveOutcome.cancelled
        }
        return PrefsSaveOutcome.failed
    }

    // ---------------------------------------------------------------- 도착(포그라운드 표시)

    /**
     * 알림이 왔다(Swift `presentation(for:)` — Android 는 FCM 서비스가 게시를 정한 뒤 조립이 부른다). 해당 스토어를 새로고침하고 보일지 정한다.
     * 모르는 알림(null)은 그대로 보인다.
     */
    fun didReceive(content: PhonePushContent?): PhonePushPresentation {
        if (content == null || !session.isSignedIn) return PhonePushPresentation.banner
        // Android 는 데이터 메시지가 앱이 뒤에 있어도(프로세스가 없어도) 서비스로 온다 — iOS 의 `willPresent` 는 앞에서만 불렸다. 뒤에서는 FCM 의
        // 짧은 실행 창 안이라 네트워크를 쓰지 않는다(E§6.3) — 재조회는 앱이 앞으로 올 때 각 스토어의 활성화가 한다.
        if (!isAppActive) return PhonePushPresentation.banner
        refreshStores(content)
        settleBadgeInForeground()
        // 확성기(계약 — 폰 푸시 · Swift presentation(for:alert:) @ a6791165): 앱을 보고 있으면 시스템 알림을 **숨기고** 앱 배너로 — 알림의
        // 제목·본문으로 바로 띄운다. 메시지함은 위 refreshStores 가 요약을 맞추고, 배너 스토어의 refresh 가 그 줄을 거를 id 를 받는다.
        val megaphone = (content as? PhonePushContent.Message)?.megaphone
        val banner = context.links.megaphoneBanner
        if (megaphone != null && banner != null) {
            presentMegaphone(banner, megaphone, content.messagePeerID)
            return PhonePushPresentation.hidden
        }
        val peer = content.messagePeerID
        val visible = context.router.visibleConversationPeerID
        if (peer != null && isAppActive && visible != null && visible.lowercase() == peer) return PhonePushPresentation.hidden
        // 근무 확인(0.3.51): 앱이 이미 앞에 있다 = 그 자체가 답이다. 위 refreshStores 가 생존 신호를 바로 보냈다 — "10분 안에 앱을 열면…" 배너를
        // 앱 안에서 띄우면 이미 연 사람에게 열라고 말하게 된다.
        if (content is PhonePushContent.WorkCheck && isAppActive) return PhonePushPresentation.hidden
        return PhonePushPresentation.banner
    }

    /**
     * 확성기 푸시 → 앱 배너. 본문이 있으면 presentFromPush 가 띄우고 스스로 refresh 한다(그래서 여기서 또 부르지 않는다 — 겹친 refresh 는
     * 한 번 더 돈다). 본문이 없는 알림(모양이 틀림)이면 띄울 것이 없으니 refresh 만 — inbox 가 신선한 것을 줄 세운다.
     */
    private fun presentMegaphone(banner: MegaphoneBannerStore, megaphone: PhonePushMegaphone, peerID: String?) {
        val body = megaphone.body.orEmpty()
        if (MegaphoneBanner.displayBody(body) == null) {
            context.scope.launch { banner.refresh() }
            return
        }
        banner.presentFromPush(megaphone.megaphoneID, senderName = megaphone.title, body = body, senderID = peerID)
    }

    private fun refreshStores(content: PhonePushContent) {
        when (content) {
            is PhonePushContent.Message -> context.links.messages?.didReceiveMessagePush(content.peerID)
            // 실시간 오목 신호와 같은 문(직렬화된 재조회 — 받은 신청이 로비·탭 배지에 곧 온다).
            is PhonePushContent.GomokuInvite -> context.gomoku.handleSignal()
            // 체스는 받은함이 없다 — 같은 직렬화된 재조회(판 중이 아니면 로비)로 받은 신청을 읽는다.
            is PhonePushContent.ChessInvite -> context.chess.handleSignal()
            is PhonePushContent.FeedbackReply -> context.links.me?.didReceiveFeedbackReplyPush(content.reportID)
            is PhonePushContent.WorkCheck -> context.links.work?.didReceiveWorkCheckPush()
        }
    }

    // ---------------------------------------------------------------- 응답(탭 · 액션)

    /** 사용자가 알림을 누르거나 액션을 골랐다. 끝날 때까지 기다린다. */
    suspend fun handleResponse(content: PhonePushContent?, action: PhonePushAction) {
        if (content == null || action == PhonePushAction.dismiss) return
        // 로그인이 풀려 있으면(복원이 로그아웃으로 끝남) 열지 않는다 — 로그인 화면이 선다.
        if (!waitForSessionSettled()) return
        // 확성기 푸시를 눌러 들어왔다: **대화로 가지 않고** 그 확성기를 배너로 띄운다(24시간 안이면 신선도 무시 — presentFromPush). 탭은 그대로.
        val megaphone = (content as? PhonePushContent.Message)?.megaphone
        val banner = context.links.megaphoneBanner
        if (megaphone != null && banner != null) {
            presentMegaphone(banner, megaphone, content.messagePeerID)
            refreshStores(content)
            return
        }
        if (action == PhonePushAction.acceptInvite) {
            when (content) {
                is PhonePushContent.GomokuInvite -> return acceptGomokuInvite(content.matchID)
                is PhonePushContent.ChessInvite -> return acceptChessInvite(content.matchID)
                else -> Unit
            }
        }
        // 탭 · 모르는 액션 · 카테고리와 맞지 않는 수락: 버리지 않고 그 화면을 연다. 배지는 앱이 앞으로 올 때 활성화의 서버 확인이 맡는다.
        // 여는 길은 **딥링크 대상 해석 한 문**이다(Swift 는 router.open 이 탭의 consumePendingRoute → routeStep · MeStore.open 을 지났다):
        // 체스·테트리스 판 중 오목 신청 · 오목·테트리스 판 중 체스 신청 → 게임 탭 첫 화면, 제보 답장 → 그 제보에 초점.
        context.openRoute(content.target)
        refreshStores(content)
    }

    /** 실행 복원이 끝날 때까지(상한) 기다린 뒤 로그인 상태인지. 가상 시간에서도 같은 상한을 쓴다. */
    private suspend fun waitForSessionSettled(): Boolean {
        if (session.phase == SessionPhase.Launching) {
            withTimeoutOrNull((sessionSettleTimeoutSeconds * 1000.0).toLong()) { session.phaseFlow.first { it != SessionPhase.Launching } }
        }
        return session.isSignedIn
    }

    /**
     * 오목 신청 수락 — 코어 오목 스토어로(루비·판 상태·받은 신청 목록이 한 곳에서 바뀐다). 판이 열렸으면 대국으로, 못 열렸으면 그 신청으로.
     * 여는 길은 전부 [PhoneContext.openRoute](딥링크 대상 해석 — 게임 탭 `routeStep`)를 지난다.
     *
     * 한 사람 한 판(B8 — 세 방향): 체스·테트리스 판이 흐르는 동안([com.yehsung.aingcheck.core.stores.games.GamesStore.gomokuEntryBlock])에는
     * **수락 RPC 를 내지 않는다**. 서버의 오목 쪽 게이트는 테트리스를 모른다 — 여기서 수락하면 흐르던 테트리스 판이 15초 침묵으로 판돈째 진다(D5).
     * GamesStore 가 로비 카드·딥링크에 거는 바로 그 가드다(알림 [수락]도 같은 입구다). 그때는 그 링크를 대상 해석에 넘긴다 → 게임 탭 첫 화면.
     */
    private suspend fun acceptGomokuInvite(matchID: String) {
        val gomoku = context.gomoku
        val generation = context.generation
        val invite = PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite(matchID))
        // 다른 오목 요청이 떠 있으면 스토어가 겹친 요청을 조용히 버린다 — 잠깐 기다린다.
        waitUntilIdle { gomoku.isBusy }
        if (generation != context.generation) return
        if (gomoku.isBusy || context.links.games?.gomokuEntryBlock != null) {
            context.openRoute(invite)
            return
        }
        gomoku.respond(matchID, accept = true)
        if (generation != context.generation) return
        if (gomoku.match?.id?.lowercase() == matchID) {
            context.openRoute(PhoneRouteTarget.Games(GamesRouteRequest.GomokuMatch(matchID)))
        } else {
            context.openRoute(invite)
        }
    }

    /**
     * 체스 신청 수락(Android 몫 — 오목과 같은 꼴). 오목·테트리스 판이 흐르는 동안([com.yehsung.aingcheck.core.stores.games.GamesStore.chessEntryBlock])
     * 에는 수락 RPC 를 내지 않고 대상 해석에 넘긴다(→ 게임 탭 첫 화면 — 한 사람 한 판).
     */
    private suspend fun acceptChessInvite(matchID: String) {
        val chess = context.chess
        val generation = context.generation
        val invite = PhoneRouteTarget.ChessInvite(matchID)
        waitUntilIdle { chess.isBusy }
        if (generation != context.generation) return
        if (chess.isBusy || context.links.games?.chessEntryBlock != null) {
            context.openRoute(invite)
            return
        }
        chess.respond(matchID, accept = true)
        if (generation != context.generation) return
        if (chess.match?.id?.lowercase() == matchID) {
            context.openRoute(PhoneRouteTarget.ChessMatch(matchID))
        } else {
            context.openRoute(invite)
        }
    }

    private suspend fun waitUntilIdle(isBusy: () -> Boolean) {
        val limitMillis = (gameBusyTimeoutSeconds * 1000.0).toLong()
        var waited = 0L
        while (isBusy() && waited < limitMillis) {
            delay(BUSY_POLL_MILLIS)
            waited += BUSY_POLL_MILLIS
        }
    }

    // ---------------------------------------------------------------- 앱 배지

    /** 배지 관찰을 건다(한 번). 적을지는 [badgeTarget] 이 정한다 — 모르면 적지 않는다. */
    private fun startBadgeTracking() {
        if (badgeTrackingJob != null || system == null) return
        badgeTrackingJob = context.scope.launch {
            // 재료: 스토어 배지(Compose 스냅숏 상태) · 앎(스냅숏 상태) · 세션 단계(StateFlow — 스냅숏이 못 본다).
            combine(snapshotFlow { badgeKnowledge to badgeTotalSource() }, session.phaseFlow) { _, _ -> badgeTarget }
                .collect { target -> if (target != null) apply(target) }
        }
    }

    /**
     * 지금 아이콘에 적을 값. null = 모른다(적지 않는다 — 앞 실행이 적은 값을 둔다).
     * 실행 복원 중 · 업데이트 필요: 계정도 숫자도 모른다. 확정된 로그아웃: 0. 로그인: 앱이 앞에서 서버 확인을 마친 뒤에만 탭 배지 합.
     */
    private val badgeTarget: Int?
        get() = when (session.phase) {
            SessionPhase.SignedOut -> 0
            SessionPhase.SignedIn -> if (badgeKnowledge == BadgeKnowledge.stores) maxOf(0, badgeTotalSource()) else null
            else -> null
        }

    private fun applyBadge() {
        badgeTarget?.let(::apply)
    }

    private fun apply(total: Int) {
        val system = system ?: return
        if (lastAppliedBadge == total) return
        lastAppliedBadge = total
        system.setBadgeCount(total)
    }

    /** 포그라운드 알림 뒤: 아직 서버 확인을 못 했으면(오프라인이었다) 다시 해 본다. 확인이 끝났으면 관찰이 적는다. */
    private fun settleBadgeInForeground() {
        if (!isAppActive || badgeKnowledge == BadgeKnowledge.stores) return
        confirmBadge()
    }

    /** 서버에서 배지 재료를 읽어 앎을 세운다. 도는 중이면 뒤따르는 한 번으로 합친다. */
    private fun confirmBadge(): Job? {
        if (system == null || !session.isSignedIn) return null
        badgeConfirmTask?.let { running ->
            badgeConfirmAgain = true
            return running
        }
        val generation = context.generation
        val job = context.scope.launch(start = CoroutineStart.LAZY) {
            do {
                badgeConfirmAgain = false
                performBadgeConfirmation(generation)
                if (generation != context.generation) return@launch
            } while (badgeConfirmAgain)
            badgeConfirmTask = null
        }
        badgeConfirmTask = job
        job.start()
        return job
    }

    /**
     * 한 번의 확인(앱이 앞에서만 시작한다). 요약이 한 번 답하면(`.stores`) 그때부터 탭 배지 합을 적는다. 요약 함수가 없는 서버(404 PGRST202)도
     * 답은 했다(메시지 탭이 옛 이력 규칙으로 접는다 — ⑤ 조용히 접기). 실패(오프라인)면 아무것도 적지 않는다. 답을 기다리는 사이 앱이 뒤로 갔어도
     * 적지 않는다(탭 스토어 새로고침이 끝났는지 모른다 — 다음 활성화가 다시 확인한다).
     */
    private suspend fun performBadgeConfirmation(generation: Int) {
        if (!session.isSignedIn) return
        val answered = try {
            val response = context.withSessionRetry { s -> context.service.fetchMessageUnreadSummary(s.accessToken) }
            response.summary != null
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            error == SupabaseWorkServiceError.DatabaseSchemaMissing
        }
        if (!answered || generation != context.generation || !session.isSignedIn || !isAppActive) return
        badgeKnowledge = BadgeKnowledge.stores
        applyBadge()
    }

    companion object {
        /** 설명 시트에서 "나중에"를 누르면 이만큼 다시 묻지 않는다(7일). */
        const val PRIMER_COOLDOWN_SECONDS: Double = 7.0 * 24 * 3600

        /** 기기 값(로그아웃해도 남는다) — 1970 기준 초 글자. */
        const val PRIMER_DISMISSED_AT_KEY: String = "aingcheck.push.primerDismissedAt"

        private const val BUSY_POLL_MILLIS = 50L
    }
}
