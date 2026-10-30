// 원본: 없음 — Kotlin 공용 코어 강화(윈도우 세션 10-31 관찰: A→B 직행 로그인 때 A 의 늦은 응답이 세대 가드를 지났다).
// Swift MobileSessionStore.adoptSignedInSession 도 세대를 안 올리지만 폰은 로그인·가입·재설정 화면이 로그아웃 상태에서만 열려 직행 길이 없다.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.wire.SupabaseSession
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class SessionAdoptGenerationTest {
    private val routes: (com.yehsung.aingcheck.testkit.mock.RecordedRequest) -> Reply? = { r ->
        when {
            r.rpcName == "client_release" -> releaseOK
            r.rpcName == "register_device_fcm" -> registerOK
            r.path == "/rest/v1/memberships" -> membershipOK
            else -> null
        }
    }

    @Test
    fun switchingStraightToAnotherAccountBumpsGeneration() = runTest {
        val h = SessionHarness(this, route = routes)
        h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0", userID = "user-1")
        h.store.launch()
        advanceUntilIdle()
        val before = h.store.generation
        h.store.adoptSignedInSession(SupabaseSession(h.jwtIn(3600.0, "b", subject = "user-2"), "rb", "user-2"), "b@b.co")
        advanceUntilIdle()
        assertEquals(before + 1, h.store.generation, "A→B 직행이면 A 때 캡처한 세대가 낡아야 한다")
    }

    @Test
    fun sameAccountOrAfterSignOutKeepsGeneration() = runTest {
        val h = SessionHarness(this, route = routes)
        h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0", userID = "user-1")
        h.store.launch()
        advanceUntilIdle()
        val signedIn = h.store.generation
        h.store.adoptSignedInSession(SupabaseSession(h.jwtIn(3600.0, "a2"), "r1", "user-1"), "a@b.co")
        advanceUntilIdle()
        assertEquals(signedIn, h.store.generation, "같은 계정을 다시 들이면 세대는 그대로")
    }
}
