// 원본: Tests/CheckMobileKitTests/BaseSessionTests.swift:370-458 · MobileSessionStore.swift:456-557 @ 1b8260d
// C§4 #33(토큰 짝 · 1시간 스로틀은 prefs 를 알 때만) · #41(기기 신원을 지어내지 않는다) · K5(register_device_fcm 하나 · null = 유지 ·
// 지울 때는 unregister_device 뒤 재등록).
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.device.DeviceRegistration
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class DeviceRegistrationTest {
    /** 40자 FCM 토큰 모양(공백 없는 인쇄 가능 ASCII, 대소문자 섞임 — 서버도 앱도 대소문자를 바꾸지 않는다). */
    private val tokenA = "fcmTokenA:APA91b" + "Xy_-".repeat(6)
    private val tokenB = "fcmTokenB:APA91b" + "Zq_-".repeat(6)

    private fun routes(register: (RecordedRequest) -> Reply = { registerOK }): (RecordedRequest) -> Reply? = { r ->
        when {
            r.rpcName == "client_release" -> releaseOK
            r.rpcName == "register_device_fcm" -> register(r)
            r.rpcName == "unregister_device" -> SessionFixtures.unregistered
            r.path == "/rest/v1/memberships" -> membershipOK
            r.path == "/auth/v1/token" -> auth("access-1", "r1")
            else -> null
        }
    }

    private fun bodyOf(r: RecordedRequest): JsonObject = SwiftJson.parse(r.bodyText) as JsonObject

    private fun registrations(h: SessionHarness) = h.server.requests.filter { it.rpcName == "register_device_fcm" }

    private suspend fun TestScope.signedInViaForm(h: SessionHarness) {
        h.store.signIn("a@b.co", "pw")
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
    }

    /** K5 본문: 키 넷(토큰 있으면) · p_platform 없음 · 토큰 대소문자 그대로. 토큰이 없으면 p_fcm_token 키째 빠진다(null = 서버가 기존 토큰 유지). */
    @Test
    fun registerDeviceFcmBodyCarriesFourKeysAndOmitsAbsentToken() = runTest {
        val h = SessionHarness(this, route = routes())
        signedInViaForm(h)
        val first = registrations(h).single()
        assertEquals(setOf("p_installation_id", "p_app_build", "p_app_version"), bodyOf(first).keys, "토큰 없음 → 키째 뺀다")
        assertEquals(SessionFixtures.INSTALLATION, bodyOf(first)["p_installation_id"]!!.jsonPrimitive.content)
        assertEquals("1", bodyOf(first)["p_app_build"]!!.jsonPrimitive.content)
        assertEquals("Bearer access-1", first.authorization)

        h.store.updatePushToken("  $tokenA\n")
        advanceUntilIdle()
        val second = registrations(h).last()
        assertEquals(setOf("p_installation_id", "p_app_build", "p_app_version", "p_fcm_token"), bodyOf(second).keys)
        assertEquals(tokenA, bodyOf(second)["p_fcm_token"]!!.jsonPrimitive.content, "앞뒤만 자르고 대소문자 그대로")
        assertEquals(PushPrefs(message = true, gomokuInvite = false, feedbackReply = true), h.store.pushPrefs)
        h.assertClean()
    }

    /** #33: 포그라운드는 1시간 스로틀(설정을 알 때만), 토큰이 바뀌면 즉시, 같은 토큰은 다시 안 보낸다. 모양이 아닌 토큰은 없음으로 본다. */
    @Test
    fun foregroundThrottlesForAnHourOnceSettingsAreKnown() = runTest {
        val h = SessionHarness(this, route = routes())
        signedInViaForm(h)
        h.store.updatePushToken(tokenA)
        advanceUntilIdle()
        assertEquals(2, registrations(h).size)
        h.store.updatePushToken(tokenA)
        advanceUntilIdle()
        assertEquals(2, registrations(h).size, "같은 토큰은 다시 안 보낸다")
        h.store.updatePushToken("short bad token")
        advanceUntilIdle()
        assertNull(h.store.pushToken, "모양이 아닌 토큰은 없음")
        val afterDrop = registrations(h).size
        h.store.updatePushToken(tokenA)
        advanceUntilIdle()
        val baseline = registrations(h).size
        assertEquals(afterDrop + 1, baseline)

        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(baseline, registrations(h).size, "1시간 안 포그라운드는 스로틀")
        advanceTimeBy(3_600_000)
        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(baseline + 1, registrations(h).size, "1시간이 지나면 다시")
        h.store.updatePushToken(tokenB)
        advanceUntilIdle()
        assertEquals(baseline + 2, registrations(h).size, "토큰이 바뀌면 즉시")
    }

    /** #33: 1시간 안에 다시 켠 프로세스라도 알림 설정을 모르면 한 번은 등록해 설정을 받는다. 받은 뒤 포그라운드는 다시 스로틀. */
    @Test
    fun relaunchWithinHourStillRegistersOnceToLearnSettings() = runTest {
        val first = SessionHarness(this, route = routes())
        signedInViaForm(first)
        val second = SessionHarness(this, vault = first.vault, prefs = first.prefs, route = routes())
        second.store.launch()
        advanceUntilIdle()
        assertEquals(1, registrations(second).size, "설정을 모르는 새 프로세스는 스로틀을 넘는다")
        second.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, registrations(second).size, "설정을 안 뒤로는 스로틀")
    }

    /** 함수가 없는 서버(PGRST202)·`invalid` 응답은 조용히 접고 스탬프를 찍지 않는다 — 다음 포그라운드가 다시 시도한다. */
    @Test
    fun serverNotReadyRegistrationFoldsQuietlyWithoutStamp() = runTest {
        for (reply in listOf(SessionFixtures.pgrst202, Reply.Json("""{"status":"invalid"}"""))) {
            val h = SessionHarness(this, route = routes { reply })
            signedInViaForm(h)
            assertNull(h.prefs.getString(SessionPrefsKeys.deviceRegisteredAt))
            assertNull(h.store.pushPrefs)
            h.store.appDidBecomeActive()
            advanceUntilIdle()
            assertEquals(2, registrations(h).size, "스탬프가 없으니 다시 시도")
            assertEquals(SessionPhase.SignedIn, h.store.phase, "등록 실패로 로그아웃하지 않는다")
        }
    }

    /** #41: 설치 식별자를 확인하지 못하면(저장 실패) 기기 등록·알림 설정 저장을 하지 않는다 — 지어낸 id 로 서버 행을 늘리지 않는다. */
    @Test
    fun unconfirmedInstallationIdentityNeverRegisters() = runTest {
        val h = SessionHarness(this, installationID = null, route = routes())
        signedInViaForm(h)
        h.store.updatePushToken(tokenA)
        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(0, registrations(h).size)
        assertNull(h.store.savePushPrefs(PushPrefs(message = false)))
        assertEquals(0, h.server.count("/rest/v1/rpc/set_push_prefs"))
        // 확인되면 그 값으로 등록한다(대조).
        h.installation.id = SessionFixtures.INSTALLATION
        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, registrations(h).size)
    }

    /**
     * K5: 토큰이 **사라지면**(알림 권한 꺼짐) `unregister_device` 뒤 토큰 없이 다시 등록한다 — 토큰을 빼고 register 만 부르면 서버가 옛 토큰을
     * 유지해 푸시가 멈추지 않는다. 대조: 토큰이 없던 상태에서 null 이 와도 해제하지 않는다.
     */
    @Test
    fun droppingTokenUnregistersThenRegistersWithoutToken() = runTest {
        val h = SessionHarness(this, route = routes())
        signedInViaForm(h)
        h.store.updatePushToken(null)
        advanceUntilIdle()
        assertEquals(0, h.server.count("/rest/v1/rpc/unregister_device"), "없던 토큰이 null — 해제하지 않는다")

        h.store.updatePushToken(tokenA)
        advanceUntilIdle()
        val before = h.server.requests.size
        h.store.updatePushToken(null)
        advanceUntilIdle()
        val after = h.server.requests.drop(before)
        assertEquals(listOf("unregister_device", "register_device_fcm"), after.map { it.rpcName })
        assertTrue("p_fcm_token" !in bodyOf(after[1]).keys, "토큰 없이 재등록")
        assertNull(h.prefs.getBoolean(SessionStore.PUSH_TOKEN_DROP_PENDING), "표식은 해제 뒤 내린다")
    }

    /** Windows(보류)는 푸시 기기 행이 없다 — 등록·해제 요청 0. */
    @Test
    fun windowsNeverRegistersDevices() = runTest {
        val windows = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, 1, "0.1.0"), "Windows 11")
        val h = SessionHarness(this, appInfo = windows, route = routes())
        assertEquals(DeviceRegistration.None, DeviceRegistration.forPlatform(ClientPlatform.WINDOWS))
        signedInViaForm(h)
        h.store.updatePushToken(tokenA)
        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(0, registrations(h).size)
        assertEquals(0, h.server.count("/rest/v1/rpc/unregister_device"))
        assertNull(h.store.pushToken, "Windows 는 푸시 토큰을 저장하지도 않는다")
        h.assertClean()
    }

    @Test
    fun fcmTokenShape() {
        val fcm = DeviceRegistration.Fcm
        assertEquals(tokenA, fcm.normalizedToken(tokenA))
        assertNull(fcm.normalizedToken("a".repeat(31)), "32자 미만")
        assertEquals("a".repeat(32), fcm.normalizedToken("a".repeat(32)))
        assertNull(fcm.normalizedToken("has space " + "a".repeat(40)))
        assertNull(fcm.normalizedToken("한글" + "a".repeat(40)))
        assertNull(fcm.normalizedToken("a".repeat(4097)))
        assertNull(fcm.normalizedToken(null))
    }
}
