// 원본: 없음 — 세션 시험 조립(Swift 시험은 각 시험이 MobileSessionStore 를 직접 만든다 — BaseSessionTests.swift 의 makeStore 자리).
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.device.DeviceRegistration
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.mock.PhoneForbiddenCalls
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.TestScope
import kotlin.test.assertEquals

/**
 * 세션 스토어 한 벌 + 스텁 서버 + 금고·설정·설치 id·가드.
 *
 * 스토어의 부모 스코프는 [storeScope] — 시험 디스패처 위의 **전경** 작업이다. `backgroundScope` 를 쓰면 `advanceUntilIdle()` 이
 * 배경 작업(기기 등록 · 소속 읽기 · 장부 정리)을 기다리지 않아 "요청 0" 이 거짓 초록/거짓 빨강이 된다(실측). 시험이 끝나면
 * `backgroundScope` 가 닫히는 순간 함께 취소한다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SessionHarness(
    val scope: TestScope,
    appInfo: AppInfo = SessionFixtures.androidInfo,
    installationID: String? = SessionFixtures.INSTALLATION,
    grants: Boolean = true,
    deviceRegistration: DeviceRegistration = DeviceRegistration.forPlatform(appInfo.platform),
    /** 지난 실행의 금고·설정을 그대로 이어 받을 때(같은 기기의 다음 실행). */
    val vault: CountingVault = CountingVault(),
    val prefs: MemoryPrefs = MemoryPrefs(),
    route: (RecordedRequest) -> Reply?,
) {
    val server = StubServer(scope, route)
    val clock = SessionFixtures.clock(scope)
    private val storeJob = SupervisorJob()
    val storeScope: CoroutineScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + storeJob)
    val installation = FixedInstallation(installationID)
    val guard = TestGuard(grants)
    private var cleanupIDs = 0
    val store = SessionStore(
        service = server.service(clock),
        vault = vault,
        prefs = prefs,
        appInfo = appInfo,
        installationIdentity = installation,
        clock = clock,
        instanceGuard = guard,
        parentScope = storeScope,
        deviceRegistration = deviceRegistration,
        newCleanupID = { "cleanup-${++cleanupIDs}" },
    )

    init {
        scope.backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
    }

    /** 금고·설정에 지난 실행의 세션을 심는다(실행 복원 재료). */
    fun seed(access: String, refresh: String?, userID: String = "user-1", email: String? = "a@b.co") {
        vault.write(access, SessionVaultKeys.accessToken)
        if (refresh != null) vault.write(refresh, SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, userID)
        if (email != null) prefs.putString(SessionPrefsKeys.email, email)
        vault.resetCounts()
    }

    fun now(): SwiftDate = clock.now()

    fun jwtIn(seconds: Double, salt: String, subject: String = "user-1"): String =
        SessionFixtures.jwt(now().addingTimeInterval(seconds), subject, salt)

    val vaultAccess: String? get() = vaultPeek(SessionVaultKeys.accessToken)
    val vaultRefresh: String? get() = vaultPeek(SessionVaultKeys.refreshToken)

    private fun vaultPeek(key: String): String? = vault.peek(key)

    /** 끝 단언 둘: 모르는 요청 0 · 폰 금지 호출 0(C§4 #13 — Android 스토어 시험 끝마다 violations == []). */
    fun assertClean() {
        assertEquals(emptyList(), server.unrouted.map { it.key }, "경로 없는 요청")
        assertEquals(emptyList(), PhoneForbiddenCalls.violations(server.requests), "폰 금지 호출")
    }
}
