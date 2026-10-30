// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.JWTClaims
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.deleteAvatarIfAny
import com.yehsung.aingcheck.core.net.deleteMyAccount
import com.yehsung.aingcheck.core.net.fetchClientRelease
import com.yehsung.aingcheck.core.net.fetchOwnMembership
import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.net.logoutLocalScope
import com.yehsung.aingcheck.core.net.refreshSession
import com.yehsung.aingcheck.core.net.setPushPrefs
import com.yehsung.aingcheck.core.net.signIn
import com.yehsung.aingcheck.core.net.signOut
import com.yehsung.aingcheck.core.net.unregisterDevice
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.session.device.DeviceRegistration
import com.yehsung.aingcheck.core.session.refresh.SessionRefreshCoordinator
import com.yehsung.aingcheck.core.session.signout.SignOutCleanup
import com.yehsung.aingcheck.core.session.signout.SignOutCleanupLedger
import com.yehsung.aingcheck.core.session.signout.SignOutCleanupOutcome
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.cancellation.CancellationException
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * 세션의 **유일한 주인**(Swift `MobileSessionStore` — C§3.2 D-1). Android·Windows 공용.
 *
 * 지키는 것(Swift 머리 주석 그대로)
 * - **살아 있는 세션**의 갱신 주체는 이 스토어의 [refreshCoordinator] 하나다(401 재시도 · 실행 직후 만료 토큰 · 실시간 선제 갱신이 모두
 *   같은 문, C§4 #4). 위젯·백그라운드 작업은 갱신하지 않는다(두 프로세스가 refresh token 을 돌리면 재사용 감지로 강제 로그아웃).
 *   로그아웃한 세션의 서버 정리(장부)는 그 세션 토큰을 혼자 쥔 장부가 직렬로 한 번 갱신한다 — 결과를 스토어 세션에 쓰지 않는다.
 * - **치명 오류만 로그아웃**한다(`AuthErrorRules.classify`). 네트워크·5xx·429 는 세션을 유지한다(C§4 #3 · #40 비행기 모드).
 * - 세대([sessionGeneration])는 로그아웃·치명 만료 때 오른다. 모든 스토어가 응답을 적용하기 전에 캡처한 세대와 비교한다.
 * - **폰 금지 호출을 하지 않는다**: app_build PATCH · 지갑 동기화 · 근무 루프 없음(C§4 #13).
 * - Windows: 단일 실행 가드([SingleInstanceGuard])를 잡지 못하면 세션을 **시작하지 않는다**([SessionPhase.AnotherInstanceRunning]).
 *
 * 실행 규약(Swift `@MainActor` 자리): 공개 함수는 한 디스패처(앱 = 메인, 시험 = runTest)에서 부른다. 띄우는 작업은 [scope] 에서 돈다 —
 * 부모 스코프를 따르되 SupervisorJob 이라 한 작업의 실패가 형제(합류 갱신·등록·장부)를 죽이지 않는다.
 *
 * 노출(K8): 값마다 지금 값(Swift 이름 그대로)과 `…Flow`(화면이 모은다) 둘을 둔다.
 */
@OptIn(ExperimentalUuidApi::class)
class SessionStore(
    override val service: SupabaseWorkService,
    private val vault: TokenVault,
    /** 비밀 아닌 설정(Swift 공용 suite `storage.defaults` 자리). */
    val prefs: KeyValueStore,
    val appInfo: AppInfo,
    private val installationIdentity: InstallationIdentity,
    /** 세션 시계. 로그인 아래 화면(재설정 쿨다운)이 같은 시계를 쓴다. */
    val clock: SessionClock,
    /** Windows: 이름 있는 뮤텍스. Android: 늘 잡히는 구현. **세션 시작 전 필수**(C§3.4) — null 을 받지 않는다. */
    private val instanceGuard: SingleInstanceGuard,
    parentScope: CoroutineScope,
    private val deviceRegistration: DeviceRegistration = DeviceRegistration.forPlatform(appInfo.platform),
    /** 정리 장부 한 줄의 id(Swift `UUID().uuidString.lowercased()`). 시험이 고정한다 — 서버로 나가지 않는다. */
    private val newCleanupID: () -> String = { Uuid.random().toString().lowercase() },
) : SessionHost {
    /** 세션 작업이 도는 자리(부모를 따르는 SupervisorJob). */
    val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))

    /** 갱신의 단일 주체(프로세스당 하나 — 이 스토어가 쥔다). */
    val refreshCoordinator: SessionRefreshCoordinator = SessionRefreshCoordinator(scope)

    private val _phase = MutableStateFlow<SessionPhase>(SessionPhase.Launching)
    private val _session = MutableStateFlow<SupabaseSession?>(null)
    private val _profile = MutableStateFlow<SessionProfile?>(null)
    private val _generation = MutableStateFlow(0)
    private val _notice = MutableStateFlow<String?>(null)
    private val _isSigningIn = MutableStateFlow(false)
    private val _pushPrefs = MutableStateFlow<PushPrefs?>(null)
    private val _latestBuild = MutableStateFlow<Long?>(null)
    private val _isDeletingAccount = MutableStateFlow(false)

    val phase: SessionPhase get() = _phase.value
    val phaseFlow: StateFlow<SessionPhase> = _phase.asStateFlow()

    override val session: SupabaseSession? get() = _session.value
    val sessionFlow: StateFlow<SupabaseSession?> = _session.asStateFlow()

    val profile: SessionProfile? get() = _profile.value
    val profileFlow: StateFlow<SessionProfile?> = _profile.asStateFlow()

    /** 로그아웃·치명 만료마다 +1. 늦게 도착한 응답을 버리는 기준. */
    val generation: Int get() = _generation.value
    override val sessionGeneration: Int get() = _generation.value
    val generationFlow: StateFlow<Int> = _generation.asStateFlow()

    /** 로그인 화면 한 줄(실패 원인 · "다시 로그인 필요"). 화면이 지울 수 있다(Swift `package var notice`). */
    var notice: String?
        get() = _notice.value
        set(value) {
            _notice.value = value
        }
    val noticeFlow: StateFlow<String?> = _notice.asStateFlow()

    val isSigningIn: Boolean get() = _isSigningIn.value
    val isSigningInFlow: StateFlow<Boolean> = _isSigningIn.asStateFlow()

    /** 지금 로그인 상태가 **로그인 폼 제출**로 시작됐는가(실행 복원이면 false). */
    var signedInViaForm: Boolean = false
        private set

    /** 마지막으로 받은 알림 설정(기기 등록 응답). 나 탭 설정 화면이 읽는다. */
    val pushPrefs: PushPrefs? get() = _pushPrefs.value
    val pushPrefsFlow: StateFlow<PushPrefs?> = _pushPrefs.asStateFlow()

    /** 서버가 알려 준 최신 빌드(업데이트 안내 — 최소 빌드 이상이면 막지는 않는다). */
    val latestBuild: Long? get() = _latestBuild.value
    val latestBuildFlow: StateFlow<Long?> = _latestBuild.asStateFlow()

    /** 계정 삭제가 도는 중(재인증 → RPC → 로컬 정리). 화면은 이 동안 버튼을 잠근다. */
    val isDeletingAccount: Boolean get() = _isDeletingAccount.value
    val isDeletingAccountFlow: StateFlow<Boolean> = _isDeletingAccount.asStateFlow()

    /** 로그인 상태가 된 순간(실행 복원 포함). 앱 조립이 실시간·탭 스토어를 깨운다. */
    var onSignedIn: (() -> Unit)? = null

    /** 로그아웃·치명 만료로 세대가 바뀐 순간. 앱 조립이 모든 스토어를 `reset()` 한다. */
    var onSignedOut: (() -> Unit)? = null

    /** 토큰이 갱신된 순간(어느 경로든). 실시간 러너가 채널에 새 토큰을 민다. */
    var onAccessTokenChanged: ((String) -> Unit)? = null

    /**
     * 로컬 사용자 데이터를 지운 직후(로그아웃 · 만료 · 삭제). Swift 는 여기서 위젯 스냅숏을 지우고 타임라인을 새로 그렸다 —
     * Android 는 위젯 몫(W2-f feature/phone)이 이 고리에 붙는다. 할 일 파일은 남긴다(사용자별 파일 · 못 올린 변경).
     */
    var onLocalUserDataCleared: () -> Unit = {}

    /** client_release 대기 상한(밀리초, 시험이 줄인다). 0 이하면 상한 없음. */
    var clientReleaseTimeoutMillis: Long = DEFAULT_CLIENT_RELEASE_TIMEOUT_MILLIS

    private var registrationJob: Job? = null
    private var registrationQueued: DeviceRegistrationReason? = null
    private var cleanupJob: Job? = null
    private var cleanupRerunRequested = false
    private var profileJob: Job? = null
    private var instanceHeld = false
    private var confirmedInstallationID: String? = null

    val isSignedIn: Boolean get() = _phase.value == SessionPhase.SignedIn && _session.value != null
    val userID: String? get() = _session.value?.userID

    /** 마지막으로 받은 푸시 토큰(FCM). 실행 사이에 남는다. */
    val pushToken: String? get() = prefs.getString(SessionPrefsKeys.pushToken)

    val storedEmail: String? get() = prefs.getString(SessionPrefsKeys.email)

    // ------------------------------------------------------------------ 단일 실행 가드(⑦)

    /** 가드를 한 번 잡으면 이 스토어가 살아 있는 동안 쥔다. 못 잡으면 false — 세션을 시작하지 않는다. */
    private fun acquireInstance(): Boolean {
        if (instanceHeld) return true
        if (!instanceGuard.tryAcquire()) return false
        instanceHeld = true
        return true
    }

    /** 앱이 끝날 때(Windows 트레이 종료). 쥔 가드를 놓는다. */
    fun releaseInstance() {
        if (!instanceHeld) return
        instanceHeld = false
        instanceGuard.release()
    }

    private fun refuseAnotherInstance() {
        _notice.value = SessionText.anotherInstanceRunning
        _phase.value = SessionPhase.AnotherInstanceRunning
    }

    // ------------------------------------------------------------------ 실행

    /**
     * 실행 순서: 단일 실행 가드 → client_release(anon, 상한 [clientReleaseTimeoutMillis]) → 빌드 < 최소면 업데이트 화면 → 금고 복원 →
     * 곧 만료면 갱신 → 로그인 상태. client_release 를 한 번 지난 뒤(결과와 무관) 지난 로그아웃의 못 한 서버 정리를 뒤에서 갚기 시작한다.
     */
    suspend fun launch() {
        if (!acquireInstance()) {
            refuseAnotherInstance()
            return
        }
        _phase.value = SessionPhase.Launching
        val startGeneration = generation

        // 함수가 없는 서버(404 · PGRST202) · `unknown_platform` · 네트워크 실패 · 상한 초과는 **막지 않는다**(C§4 #34 — 모르면 막지 않는다).
        // 최소 빌드 검사는 서버가 기능을 바꿀 때의 안전장치이지 로그인의 조건이 아니다.
        val release = fetchClientReleaseWithinLimit()
        if (startGeneration != generation) return
        settleSignOutCleanup()
        if (release != null) {
            _latestBuild.value = release.latestBuild
            val minBuild = release.minBuild
            if (release.status == "ok" && minBuild != null && appInfo.build < minBuild) {
                _phase.value = SessionPhase.NeedsUpdate(minBuild)
                return
            }
        }

        val restored = restoredSession()
        if (restored == null) {
            _phase.value = SessionPhase.SignedOut
            return
        }
        _session.value = restored

        val expiry = JWTClaims.expiry(restored.accessToken)
        if (expiry != null && expiry.timeIntervalSince(clock.now()) < LAUNCH_REFRESH_LEAD_SECONDS) {
            try {
                refreshViaCoordinator(generation)
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (startGeneration != generation) return
                when (AuthErrorRules.classify(error)) {
                    AuthErrorDisposition.fatal -> {
                        expireSession(AuthErrorRules.message(error, SessionText.signInAgain))
                        return
                    }
                    // 세션을 유지한다 — 다음 요청의 401 재시도가 다시 갱신한다(비행기 모드로 켠 폰이 로그아웃되지 않게, C§4 #40).
                    AuthErrorDisposition.cancelled, AuthErrorDisposition.transient -> Unit
                }
            }
        }
        if (startGeneration != generation || _session.value == null) return
        enterSignedIn()
    }

    /**
     * client_release 를 상한 안에서만 기다린다. 응답이면 그 값, 실패·상한 초과면 null(= 모름). 상한을 넘으면 요청을 취소한다 —
     * 늦게 온 결과로 이미 로그인한 화면을 업데이트 화면으로 뒤집지 않는다(다음 실행이 다시 본다).
     */
    private suspend fun fetchClientReleaseWithinLimit(): ClientReleaseResponse? {
        val limit = clientReleaseTimeoutMillis
        val platform = appInfo.platform.wire
        suspend fun fetch(): ClientReleaseResponse? = try {
            service.fetchClientRelease(platform)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            null
        }
        return if (limit > 0) withTimeoutOrNull(limit) { fetch() } else fetch()
    }

    // ------------------------------------------------------------------ 로그인 · 로그아웃

    suspend fun signIn(email: String, password: String) {
        val trimmedEmail = email.trim()
        if (trimmedEmail.isEmpty() || password.isEmpty()) {
            _notice.value = SessionText.missingCredentials
            return
        }
        if (_isSigningIn.value) return
        if (!acquireInstance()) {
            refuseAnotherInstance()
            return
        }
        _isSigningIn.value = true
        _notice.value = null
        val startGeneration = generation
        try {
            val signedIn = service.signIn(trimmedEmail, password)
            if (startGeneration != generation) return
            adoptSignedInSession(signedIn, trimmedEmail)
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (startGeneration != generation) return
            when (AuthErrorRules.classify(error)) {
                AuthErrorDisposition.cancelled -> return
                AuthErrorDisposition.transient -> _notice.value = SessionText.network
                AuthErrorDisposition.fatal -> _notice.value = AuthErrorRules.message(error, SessionText.signInFailed)
            }
        } finally {
            _isSigningIn.value = false
        }
    }

    /**
     * 세션을 손에 넣은 직후의 **공통 마무리**. 비밀번호 로그인·가입([com.yehsung.aingcheck.core.session.signup.SignUpStore])·
     * 비밀번호 재설정([com.yehsung.aingcheck.core.session.reset.PasswordResetStore])이 세션을 얻는 길은 셋이지만 그 뒤의 일
     * (금고 저장 · 이메일 기억 · 기기 등록 · 소속 읽기 · 못 한 로그아웃 정리)은 반드시 여기 한 곳을 지난다.
     *
     * 호출하는 쪽이 세대 가드를 지난 뒤 부른다(여기서는 세대를 다시 보지 않는다 — 두 번 재면 호출부의 가드가 공허해진다).
     *
     * **다른 계정으로 바로 바꿔 탈 때만 세대를 올린다**(A 로그인 상태에서 B 를 들임 — 로그아웃을 거치지 않아 세대가 그대로였다).
     * 안 올리면 A 때 나간 요청의 늦은 응답이 세대 가드를 지나 B 화면에 A 의 값을 적는다(윈도우 세션 10-31 실재현: 지갑 잔량).
     * 같은 계정을 다시 들이거나 로그아웃 뒤 들이는 길(폰의 유일한 길)은 그대로다 — 호출부가 캡처한 세대가 계속 맞아야 한다.
     */
    fun adoptSignedInSession(signedIn: SupabaseSession, email: String) {
        if (!acquireInstance()) {
            refuseAnotherInstance()
            return
        }
        val previous = _session.value
        if (previous != null && previous.userID != signedIn.userID) _generation.value += 1
        persist(signedIn)
        prefs.putString(SessionPrefsKeys.email, email)
        _session.value = signedIn
        enterSignedIn(DeviceRegistrationReason.signIn)
        // 네트워크가 확실히 있는 순간 — 지난 로그아웃의 못 한 정리를 갚는다(같은 계정이면 새 기기 행은 건드리지 않는다).
        settleSignOutCleanup()
    }

    /**
     * 로그아웃(C§4 #6·#7): 세대를 올리고 **로컬을 먼저 비운 뒤** 서버에 unregister_device → logout?scope=local 순서로 알린다.
     *
     * 로컬을 먼저 비우는 이유: 두 요청을 기다리는 동안 화면은 이미 로그인 화면이어야 하고, 그 사이 다시 로그인하면 늦게 끝난 정리가
     * **새 계정의 금고를 지우는** 창이 생긴다. 서버 요청은 캡처한 토큰으로 나간다.
     * 서버 정리는 **장부에 먼저 적고** 갚는다: access token 이 만료됐으면(401) 장부의 refresh token 으로 한 번 갱신해 다시 부르고,
     * 오프라인·5xx 면 장부에 남겨 다음 실행·포그라운드·로그인 때 다시 한다.
     */
    suspend fun signOut() {
        val current = _session.value
        if (current == null) {
            _phase.value = SessionPhase.SignedOut
            return
        }
        val cleanup = SignOutCleanup(
            id = newCleanupID(),
            userID = current.userID,
            accessToken = current.accessToken,
            refreshToken = current.refreshToken,
            createdAt = clock.now().timeIntervalSince1970,
        )
        endSession(cleanup)
        settleSignOutCleanup()?.join()
    }

    /**
     * 이 기기에서 세션을 끝내는 **단 하나의 길**(로그아웃 · 계정 삭제 공용). 순서가 계약이다(C§4 #7): 세대를 올리고 · 갱신·등록을 멈추고 ·
     * (있으면) 서버 정리를 장부에 적고 · 금고·사용자 칸을 지우고 · 로그인 화면으로 · 앱 조립에 알린다.
     *
     * [cleanup] 이 null 인 쪽은 계정 삭제다 — 서버 행이 cascade 로 이미 사라졌고, 지운 계정의 refresh token 을 장부에 30일 남기는 것
     * 자체가 "다 지웠다"는 약속에 어긋난다.
     */
    private fun endSession(cleanup: SignOutCleanup?) {
        _generation.value += 1
        refreshCoordinator.invalidate()
        registrationJob?.cancel()
        registrationJob = null
        registrationQueued = null
        if (cleanup != null) {
            SignOutCleanupLedger.update(vault) { it.add(cleanup) }
        }
        clearLocalUserData()
        // 스스로 로그아웃하면 이메일도 잊는다(폰을 넘기거나 계정을 바꿀 때 앞 사람 이메일이 로그인 칸에 남지 않게).
        // 치명 만료(expireSession)는 같은 사람이 다시 들어오는 길이라 남긴다.
        prefs.remove(SessionPrefsKeys.email)
        _session.value = null
        _profile.value = null
        _pushPrefs.value = null
        _notice.value = null
        _phase.value = SessionPhase.SignedOut
        onSignedOut?.invoke()
    }

    // ------------------------------------------------------------------ 계정 삭제(C§4 #35)

    /**
     * **계정을 영구 삭제한다**. 순서가 계약이다:
     *  1. 재인증 — 저장된 이메일 + 입력한 비밀번호로 signIn 한 번. 실패하면 **RPC 를 부르지 않는다**(잠금 해제된 폰을 집은 사람이
     *     로그인 상태만으로는 못 지운다).
     *  2. 사진 먼저 — 서버 함수는 Storage 표에 직접 못 써서 avatars/<uid>.jpg 를 남긴다. 실패는 무시한다.
     *  3. `delete_my_account` — 재인증으로 받은 **새 토큰**으로 부른다.
     *  4. 성공하면 로그아웃과 같은 로컬 정리(장부 없이). 실패하면 로그인 상태를 **그대로** 두고 이유를 돌려준다(404 = 서버 준비 전 포함).
     * 재인증이 만든 두 번째 서버 세션은 RPC 가 실패했을 때 `logout?scope=local` 로 닫는다(성공했으면 cascade 로 이미 없다).
     */
    suspend fun deleteAccount(password: String): AccountDeletionOutcome {
        if (!isSignedIn) return AccountDeletionOutcome.Failed(AccountDeletionFailure.NotSignedIn)
        if (_isDeletingAccount.value) return AccountDeletionOutcome.Failed(AccountDeletionFailure.AlreadyRunning)
        if (password.isEmpty()) return AccountDeletionOutcome.Failed(AccountDeletionFailure.PasswordRequired)
        val email = _profile.value?.email ?: storedEmail
        if (email.isNullOrEmpty()) return AccountDeletionOutcome.Failed(AccountDeletionFailure.EmailUnknown)
        _isDeletingAccount.value = true
        try {
            val startGeneration = generation
            val reauth: SupabaseSession = try {
                service.signIn(email, password)
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (startGeneration != generation) return AccountDeletionOutcome.Failed(AccountDeletionFailure.NotSignedIn)
                return when (AuthErrorRules.classify(error)) {
                    AuthErrorDisposition.cancelled, AuthErrorDisposition.transient -> AccountDeletionOutcome.Failed(AccountDeletionFailure.Network)
                    AuthErrorDisposition.fatal ->
                        if (error == SupabaseWorkServiceError.InvalidLoginCredentials) {
                            AccountDeletionOutcome.Failed(AccountDeletionFailure.WrongPassword)
                        } else {
                            AccountDeletionOutcome.Failed(AccountDeletionFailure.ReauthRejected(AuthErrorRules.message(error, SessionText.signInFailed)))
                        }
                }
            }
            if (startGeneration != generation) {
                // 그 사이 로그아웃·치명 만료 — 재인증 세션만 닫고 물러난다(계정은 그대로다).
                service.signOut(reauth.accessToken)
                return AccountDeletionOutcome.Failed(AccountDeletionFailure.NotSignedIn)
            }

            service.deleteAvatarIfAny(reauth.accessToken, reauth.userID)

            try {
                service.deleteMyAccount(reauth.accessToken)
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                service.signOut(reauth.accessToken)
                if (startGeneration != generation) return AccountDeletionOutcome.Failed(AccountDeletionFailure.NotSignedIn)
                if (isMissingDeviceFunction(error)) return AccountDeletionOutcome.Failed(AccountDeletionFailure.ServerNotReady)
                return when (AuthErrorRules.classify(error)) {
                    AuthErrorDisposition.cancelled, AuthErrorDisposition.transient -> AccountDeletionOutcome.Failed(AccountDeletionFailure.Network)
                    AuthErrorDisposition.fatal -> AccountDeletionOutcome.Failed(AccountDeletionFailure.Rejected)
                }
            }
            // 서버가 지웠다. 그 사이 세대가 바뀌었으면(실시간 갱신이 치명으로 끝나 이미 로그아웃) 로컬은 이미 비었다 — 다시 비우지 않는다.
            if (startGeneration == generation) endSession(cleanup = null)
            return AccountDeletionOutcome.Deleted
        } finally {
            _isDeletingAccount.value = false
        }
    }

    /** 치명 만료(refresh token 무효 등). 서버에 알릴 토큰이 없으므로 로컬만 정리한다. 이메일은 남긴다(같은 사람이 다시 들어온다). */
    fun expireSession(message: String = SessionText.signInAgain) {
        if (_session.value == null && _phase.value != SessionPhase.SignedIn) return
        _generation.value += 1
        refreshCoordinator.invalidate()
        registrationJob?.cancel()
        registrationJob = null
        registrationQueued = null
        clearLocalUserData()
        _session.value = null
        _profile.value = null
        _pushPrefs.value = null
        _notice.value = message
        _phase.value = SessionPhase.SignedOut
        onSignedOut?.invoke()
    }

    // ------------------------------------------------------------------ 401 재시도

    /**
     * 맥 `withSessionRetry` 와 같은 모양: 세션 가드 → 세대 캡처 → 호출 → `.sessionExpired` 면 조정자 경유 갱신 1회 → 재시도.
     * 갱신이 **치명**으로 실패할 때만 로그아웃하고, 일시 실패면 세션을 유지한 채 원래 오류를 던진다(C§4 #3).
     */
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T {
        val current = _session.value ?: throw SupabaseWorkServiceError.SessionExpired
        val startGeneration = generation
        try {
            return operation(current)
        } catch (original: SupabaseWorkServiceError) {
            if (original != SupabaseWorkServiceError.SessionExpired) throw original
            if (startGeneration != generation) throw original
            if (current.refreshToken == null) {
                expireSession()
                throw original
            }
            val refreshed = try {
                refreshViaCoordinator(startGeneration)
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                if (startGeneration != generation) throw original
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.fatal) expireSession()
                throw original
            }
            if (startGeneration != generation) throw original
            return operation(refreshed)
        }
    }

    /**
     * 실시간 선제·강제 갱신. 성공하면 새 access token. 실패면 (fatal 여부) — fatal 이면 세션도 여기서 만료시킨다.
     * 갱신이 도는 사이 세대가 바뀌었으면(로그아웃 → 재로그인) 결과는 **stale** — 지금 링의 일이 아니므로 러너가 버린다.
     */
    suspend fun refreshForRealtime(): RealtimeRefreshResult {
        if (_session.value?.refreshToken == null) return RealtimeRefreshResult.Failed(fatal = _session.value == null)
        val startGeneration = generation
        return try {
            val refreshed = refreshViaCoordinator(startGeneration)
            if (startGeneration != generation) RealtimeRefreshResult.Failed.Stale else RealtimeRefreshResult.Refreshed(refreshed.accessToken)
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            if (startGeneration != generation) return RealtimeRefreshResult.Failed.Stale
            when (AuthErrorRules.classify(error)) {
                AuthErrorDisposition.fatal -> {
                    expireSession()
                    RealtimeRefreshResult.Failed(fatal = true)
                }
                AuthErrorDisposition.cancelled, AuthErrorDisposition.transient -> RealtimeRefreshResult.Failed(fatal = false)
            }
        }
    }

    private suspend fun refreshViaCoordinator(startGeneration: Int): SupabaseSession =
        refreshCoordinator.refresh(
            generation = startGeneration,
            // 호출 시점에 읽는다 — 합류하지 못한 순차 호출이 이미 회전된 옛 토큰을 재사용하지 않게(조정자 ①).
            tokenProvider = { _session.value?.refreshToken },
            refresh = { token -> service.refreshSession(token) },
            apply = { refreshed ->
                // 세대 가드(③): 로그아웃 중에 늦게 온 갱신이 새 계정·로그인 화면에 쓰이지 않는다.
                if (startGeneration == generation) {
                    _session.value = refreshed
                    persist(refreshed)
                    onAccessTokenChanged?.invoke(refreshed.accessToken)
                }
            },
        )

    // ------------------------------------------------------------------ 기기 등록(C§4 #33 · #41)

    /** 포그라운드 진입. 못 한 로그아웃 정리가 있으면 갚고(로그인 여부와 무관), 로그인 상태면 1시간 스로틀로 등록. */
    fun appDidBecomeActive() {
        settleSignOutCleanup()
        if (!isSignedIn) return
        requestDeviceRegistration(DeviceRegistrationReason.foreground)
    }

    /**
     * 푸시 토큰이 새로 왔다(FCM `onNewToken`/`onRegistered` → W2-f 가 부른다). 값이 바뀌었으면 즉시 등록한다.
     * 토큰이 **사라지면**(알림 권한 꺼짐 — W2-f 가 null 을 넘긴다) K5 규칙대로 `unregister_device` 뒤 토큰 없이 다시 등록한다 —
     * `register_device_fcm` 에 토큰을 빼고 보내면 서버가 **옛 토큰을 유지**하므로(null = 유지) 그것만으로는 푸시가 멈추지 않는다.
     */
    fun updatePushToken(raw: String?) {
        if (!deviceRegistration.isEnabled) return
        val valid = deviceRegistration.normalizedToken(raw)
        val previous = pushToken
        if (valid == previous) return
        if (valid != null) {
            prefs.putString(SessionPrefsKeys.pushToken, valid)
        } else {
            prefs.remove(SessionPrefsKeys.pushToken)
            if (previous != null) prefs.putBoolean(PUSH_TOKEN_DROP_PENDING, true)
        }
        if (!isSignedIn) return
        requestDeviceRegistration(DeviceRegistrationReason.pushTokenChanged)
    }

    /** 등록 요청. 진행 중이면 한 번만 줄 세운다(연달아 온 사건이 요청을 쌓지 않게). */
    fun requestDeviceRegistration(reason: DeviceRegistrationReason) {
        if (!isSignedIn || !deviceRegistration.isEnabled) return
        if (registrationJob != null) {
            // 로그인·토큰 변경은 스로틀을 무시해야 하므로 더 강한 이유가 이긴다.
            if (registrationQueued == null || reason != DeviceRegistrationReason.foreground) registrationQueued = reason
            return
        }
        val job = scope.launch(start = CoroutineStart.LAZY) {
            performDeviceRegistration(reason)
            val self = currentCoroutineContext().job
            if (registrationJob !== self) return@launch
            registrationJob = null
            val queued = registrationQueued
            if (queued != null) {
                registrationQueued = null
                requestDeviceRegistration(queued)
            }
        }
        registrationJob = job
        job.start()
    }

    /** 시험이 기다릴 수 있게 진행 중 등록을 돌려준다. */
    val pendingDeviceRegistration: Job? get() = registrationJob

    /**
     * 설치 식별자 — **저장 확인 뒤의 값만** 쓴다(C§4 #41 · 기억 device-identity-must-not-be-invented). 확인 실패(null)면 기기 단위 쓰기
     * (등록·해제·알림 설정)를 하지 않는다. 한 번 확인한 값은 이 실행 동안 붙잡는다.
     */
    private fun installationID(): String? =
        confirmedInstallationID ?: installationIdentity.installationId()?.also { confirmedInstallationID = it }

    private suspend fun performDeviceRegistration(reason: DeviceRegistrationReason) {
        val current = _session.value ?: return
        val installationID = installationID() ?: return
        val token = pushToken
        val signature = deviceRegistration.signature(current.userID, appInfo, token)
        val now = clock.now()
        // 스로틀은 알림 종류 설정을 이미 알 때만 건다 — 설정은 이 응답으로만 오므로, 1시간 안에 재실행한 프로세스가 건너뛰면
        // 나 탭 토글이 최대 1시간 잠긴다(iOS e2e 결함 1). 프로세스당 한 번 더 보내는 비용뿐이다.
        if (reason == DeviceRegistrationReason.foreground &&
            _pushPrefs.value != null &&
            prefs.getString(SessionPrefsKeys.deviceRegisteredSignature) == signature
        ) {
            val last = prefs.getString(SessionPrefsKeys.deviceRegisteredAt)?.toDoubleOrNull()?.let { SwiftDate(it) }
            if (last != null && now.timeIntervalSince(last) < DEVICE_REGISTRATION_THROTTLE_SECONDS && now >= last) return
        }
        val startGeneration = generation
        try {
            if (prefs.getBoolean(PUSH_TOKEN_DROP_PENDING) == true) {
                try {
                    withSessionRetry { s -> service.unregisterDevice(s.accessToken, installationID) }
                } catch (error: Throwable) {
                    rethrowIfOwnCancellation(error)
                    // 해제 함수가 없는 서버면 지울 행도 없다 — 깃발을 내리고 등록으로 간다. 그 밖(일시 실패)은 다음 기회에 다시.
                    if (!isMissingDeviceFunction(error)) throw error
                }
                prefs.remove(PUSH_TOKEN_DROP_PENDING)
            }
            val response = withSessionRetry { s -> deviceRegistration.register(service, s.accessToken, installationID, appInfo, token) }
            if (startGeneration != generation) return
            if (response.status == "ok") {
                prefs.putString(SessionPrefsKeys.deviceRegisteredAt, now.timeIntervalSince1970.toString())
                prefs.putString(SessionPrefsKeys.deviceRegisteredSignature, signature)
                response.pushPrefs?.let { _pushPrefs.value = it }
            }
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            // 함수가 없는 서버(PGRST202)·`invalid`·일시 실패는 조용히 — 다음 포그라운드가 다시 시도한다(스탬프를 안 찍었으므로).
        }
    }

    /** 알림 설정 저장(나 탭 → W2-f 푸시 조정자가 부른다). 성공하면 새 설정, 아니면 null. */
    suspend fun savePushPrefs(prefsValue: PushPrefs): PushPrefs? {
        val installationID = installationID() ?: return null
        val startGeneration = generation
        val response = withSessionRetry { s -> service.setPushPrefs(s.accessToken, installationID, prefsValue) }
        if (startGeneration != generation) return null
        val saved = response.pushPrefs
        if (response.status == "ok" && saved != null) {
            _pushPrefs.value = saved
            return saved
        }
        return null
    }

    // ------------------------------------------------------------------ 로그아웃 서버 정리(장부)

    /** 장부에 못 한 정리가 남아 있는가(금고를 읽는다 — 진단·시험). */
    val hasPendingSignOutCleanup: Boolean get() = SignOutCleanupLedger.load(vault).isNotEmpty()

    /** 진행 중인 정리(시험이 기다린다). */
    val pendingSignOutCleanup: Job? get() = cleanupJob

    /**
     * 장부를 갚는다. 이미 돌고 있으면 한 바퀴 더 돌게 표시하고 그 작업을 돌려준다(직렬 — 같은 refresh token 을 두 번 쓰지 않는다).
     * 장부가 비었으면 아무 요청도 만들지 않고 null.
     */
    fun settleSignOutCleanup(): Job? {
        val running = cleanupJob
        if (running != null) {
            cleanupRerunRequested = true
            return running
        }
        if (!hasPendingSignOutCleanup) return null
        val job = scope.launch(start = CoroutineStart.LAZY) {
            var finished: Boolean
            do {
                cleanupRerunRequested = false
                finished = settleCleanupPass()
            } while (finished && cleanupRerunRequested)
            if (cleanupJob === currentCoroutineContext().job) cleanupJob = null
        }
        cleanupJob = job
        job.invokeOnCompletion { if (cleanupJob === job) cleanupJob = null }
        job.start()
        return job
    }

    /** 장부 한 바퀴. 일시 실패를 만나면 거기서 멈추고 false(오프라인이면 나머지도 어차피 실패한다). */
    private suspend fun settleCleanupPass(): Boolean {
        val now = clock.now().timeIntervalSince1970
        SignOutCleanupLedger.update(vault) { entries -> entries.removeAll { now - it.createdAt > SignOutCleanupLedger.maxAgeSeconds } }
        for (entry in SignOutCleanupLedger.load(vault)) {
            when (val outcome = settle(entry)) {
                SignOutCleanupOutcome.Settled ->
                    SignOutCleanupLedger.update(vault) { entries -> entries.removeAll { it.id == entry.id } }
                is SignOutCleanupOutcome.RetryLater -> {
                    SignOutCleanupLedger.update(vault) { entries ->
                        val index = entries.indexOfFirst { it.id == outcome.entry.id }
                        if (index >= 0) entries[index] = outcome.entry
                    }
                    return false
                }
            }
        }
        return true
    }

    /** 정리 한 건의 진행(Swift 의 `inout entry` · `inout refreshed` 자리). */
    private class CleanupCursor(var entry: SignOutCleanup, var refreshed: Boolean = false)

    private enum class CleanupStep { retry, later, giveUp, skip }

    /** 정리 한 건: unregister_device(이 설치) → logout?scope=local. 401 은 한 번 갱신해 다시, 일시 실패는 나중에. */
    private suspend fun settle(start: SignOutCleanup): SignOutCleanupOutcome {
        val cursor = CleanupCursor(start)

        // 같은 계정으로 다시 로그인해 있으면 이 설치의 기기 행은 **새 세션의 것**이다 — 지우지 않고 옛 세션만 끊는다.
        if (!cursor.entry.deviceUnregistered && isSignedIn && _session.value?.userID == cursor.entry.userID) {
            cursor.entry = cursor.entry.copy(deviceUnregistered = true)
        }
        // 확인된 설치 식별자가 없으면 이 설치로 올린 기기 행도 없다(지어낸 id 로 등록하지 않았다 — C§4 #41).
        val installationID = installationID()
        if (!cursor.entry.deviceUnregistered && (installationID == null || !deviceRegistration.isEnabled)) {
            cursor.entry = cursor.entry.copy(deviceUnregistered = true)
        }

        while (!cursor.entry.deviceUnregistered) {
            try {
                service.unregisterDevice(cursor.entry.accessToken, installationID!!)
                cursor.entry = cursor.entry.copy(deviceUnregistered = true)
                // 이 요청이 떠 있는 사이 같은 계정으로 다시 로그인해 행을 새로 올렸을 수 있다 — 방금 지웠으니 다시 올린다.
                if (isSignedIn && _session.value?.userID == cursor.entry.userID) {
                    requestDeviceRegistration(DeviceRegistrationReason.signIn)
                }
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                when (cleanupStep(error, cursor)) {
                    CleanupStep.retry -> continue
                    CleanupStep.later -> return SignOutCleanupOutcome.RetryLater(cursor.entry)
                    CleanupStep.giveUp -> return SignOutCleanupOutcome.Settled
                    CleanupStep.skip -> cursor.entry = cursor.entry.copy(deviceUnregistered = true)
                }
            }
        }

        while (true) {
            try {
                service.logoutLocalScope(cursor.entry.accessToken)
                return SignOutCleanupOutcome.Settled
            } catch (error: Throwable) {
                rethrowIfOwnCancellation(error)
                when (cleanupStep(error, cursor)) {
                    CleanupStep.retry -> continue
                    CleanupStep.later -> return SignOutCleanupOutcome.RetryLater(cursor.entry)
                    CleanupStep.giveUp, CleanupStep.skip -> return SignOutCleanupOutcome.Settled
                }
            }
        }
    }

    /**
     * 정리 실패의 처분.
     * - 네트워크 · 5xx · 429 · 취소 → later(장부에 남긴다)
     * - 401(만료) → 붙잡아 둔 refresh token 으로 **한 번** 갱신해 retry. 회전한 토큰은 곧바로 장부에 쓴다(여기서 앱이 죽어도 옛 토큰을
     *   다시 쓰지 않게). 갱신이 치명(invalid_grant)이거나 이미 한 번 갱신했으면 giveUp(알릴 방법이 없다).
     * - 그 밖(함수 없는 서버 404 · 400 · 403) → skip(이 단계는 할 수 없다 — 다음 단계로)
     */
    private suspend fun cleanupStep(error: Throwable, cursor: CleanupCursor): CleanupStep {
        if (AuthErrorRules.classify(error) != AuthErrorDisposition.fatal) return CleanupStep.later
        if (error != SupabaseWorkServiceError.SessionExpired) return CleanupStep.skip
        val refreshToken = cursor.entry.refreshToken
        if (cursor.refreshed || refreshToken == null) return CleanupStep.giveUp
        cursor.refreshed = true
        return try {
            val fresh = service.refreshSession(refreshToken)
            cursor.entry = cursor.entry.copy(accessToken = fresh.accessToken, refreshToken = fresh.refreshToken)
            val rotated = cursor.entry
            SignOutCleanupLedger.update(vault) { entries ->
                val index = entries.indexOfFirst { it.id == rotated.id }
                if (index >= 0) entries[index] = rotated
            }
            CleanupStep.retry
        } catch (refreshError: Throwable) {
            rethrowIfOwnCancellation(refreshError)
            if (AuthErrorRules.classify(refreshError) == AuthErrorDisposition.fatal) CleanupStep.giveUp else CleanupStep.later
        }
    }

    // ------------------------------------------------------------------ 프로필

    /** 팀 소속을 읽어 프로필을 채운다(읽기만). 실패는 조용히 — 탭이 다시 부를 수 있다. */
    suspend fun refreshProfile() {
        val current = _session.value ?: return
        val startGeneration = generation
        try {
            val membership = withSessionRetry { s -> service.fetchOwnMembership(s.accessToken, s.userID) }
            if (startGeneration != generation) return
            val base = _profile.value ?: SessionProfile(userID = current.userID, email = storedEmail)
            _profile.value = base.copy(
                teamID = membership?.teamID,
                teamName = membership?.teamName,
                teamGoalHours = membership?.goalHours,
                teamRole = membership?.role,
            )
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
        }
    }

    /** 로그인 직후 띄운 소속 읽기(시험이 기다린다). */
    val pendingProfileRefresh: Job? get() = profileJob

    // ------------------------------------------------------------------ 저장

    private fun enterSignedIn(registrationReason: DeviceRegistrationReason = DeviceRegistrationReason.foreground) {
        val current = _session.value ?: return
        if (_profile.value?.userID != current.userID) {
            _profile.value = SessionProfile(userID = current.userID, email = storedEmail)
        }
        _notice.value = null
        signedInViaForm = registrationReason == DeviceRegistrationReason.signIn
        _phase.value = SessionPhase.SignedIn
        onSignedIn?.invoke()
        requestDeviceRegistration(registrationReason)
        profileJob = scope.launch { refreshProfile() }
    }

    private fun restoredSession(): SupabaseSession? {
        val userID = prefs.getString(SessionPrefsKeys.userID)
        if (userID.isNullOrEmpty()) return null
        val access = vault.read(SessionVaultKeys.accessToken)
        if (access.isNullOrEmpty()) return null
        val refresh = vault.read(SessionVaultKeys.refreshToken)
        return SupabaseSession(accessToken = access, refreshToken = refresh, userID = userID)
    }

    private fun persist(session: SupabaseSession) {
        vault.write(session.accessToken, SessionVaultKeys.accessToken)
        val refresh = session.refreshToken
        if (refresh != null) {
            vault.write(refresh, SessionVaultKeys.refreshToken)
        } else {
            vault.delete(SessionVaultKeys.refreshToken)
        }
        prefs.putString(SessionPrefsKeys.userID, session.userID)
    }

    /** 금고 토큰 · 사용자 칸을 지우고 위젯 고리를 부른다. 할 일 파일은 남긴다(사용자별 파일 · 못 올린 변경 — 맥과 같은 관용). */
    private fun clearLocalUserData() {
        vault.delete(SessionVaultKeys.accessToken)
        vault.delete(SessionVaultKeys.refreshToken)
        for (key in SessionPrefsKeys.userScopedKeys) prefs.remove(key)
        onLocalUserDataCleared()
    }

    companion object {
        /** 1시간 스로틀(Swift `deviceRegistrationThrottleSeconds`). */
        const val DEVICE_REGISTRATION_THROTTLE_SECONDS: Double = 3600.0

        /** 실행 직후 이 초 안에 만료되는 토큰은 먼저 갱신한다. */
        const val LAUNCH_REFRESH_LEAD_SECONDS: Double = 60.0

        /**
         * 실행 때 client_release 를 기다리는 상한(C§4 #34 — 3초). 느린 망에서 금고에 멀쩡한 세션이 있어도 첫 화면이 요청 15초·리소스
         * 30초 동안 스피너에 머물지 않게. 넘으면 "모름"으로 접고 복원으로 넘어간다(오프라인과 같은 관용).
         */
        const val DEFAULT_CLIENT_RELEASE_TIMEOUT_MILLIS: Long = 3_000

        /** 토큰을 지운 뒤 아직 `unregister_device` 를 못 한 표식(기기 값 — 사용자 칸이 아니다). */
        const val PUSH_TOKEN_DROP_PENDING: String = "aingcheck.push.tokenDropPending"
    }
}
