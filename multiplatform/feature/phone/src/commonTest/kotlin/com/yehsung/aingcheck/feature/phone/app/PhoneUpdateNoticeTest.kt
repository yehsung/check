// 원본: Tests/CheckMobileKitTests/V1016UpdateNoticeTests.swift(값이 오는 길 · 실행 한 번 · 닫기 · 로그아웃 · 재실행) @ 1a5eeca6
// 앱 모델 전체(스텁 서버 + PhoneAppModel)로 잰다: client_release 응답 → 세션 latestBuild → 지금 탭 안내 → 닫은 빌드 저장(앱 단위).
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneUpdateNoticeTest {
    /** 하네스의 이 빌드는 7 이다(PhoneHarness). */
    private fun release(latest: Long): Reply = Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":$latest}""")

    private fun TestScope.launched(reply: Reply, prefs: Map<String, Any> = emptyMap()): PhoneHarness {
        // 재실행 = 앞 실행의 저장소로 앱 모델을 새로 만드는 것이다(스토어는 만들어질 때 저장값을 읽는다).
        val h = PhoneHarness(this, initialPrefs = prefs) { r -> if (r.rpcName == "client_release") reply else null }
        h.signIn()
        return h
    }

    @Test
    fun releaseResponseReachesTheNotice() = runTest {
        val h = launched(release(8))
        assertEquals(SessionPhase.SignedIn, h.app.session.phase)
        assertEquals(8L, h.app.session.latestBuild)
        assertTrue(h.app.now.showsUpdateNotice, "client_release 가 지금 탭 안내까지 오지 않았다")
    }

    @Test
    fun noNoticeWithoutANewerBuild() = runTest {
        val cases = listOf(
            Triple(release(7), 7L, "같음"),
            Triple(release(6), 6L, "낮음"),
            Triple(Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":null}"""), null, "값 없음"),
            Triple(Reply.missingFunction, null, "함수 없음"),
        )
        for ((reply, latest, name) in cases) {
            val h = launched(reply)
            assertEquals(SessionPhase.SignedIn, h.app.session.phase, name)
            assertEquals(latest, h.app.session.latestBuild, name)
            assertFalse(h.app.now.showsUpdateNotice, name)
        }
    }

    /** 실행 때 한 번만 묻는다 — 앞으로 돌아와도 client_release 가 늘지 않는다. */
    @Test
    fun foregroundDoesNotAskAgain() = runTest {
        val h = launched(release(8))
        val before = h.server.requests.count { it.rpcName == "client_release" }
        assertEquals(1, before)
        // active 동안은 주기 폴링이 돌아 가상 시간이 끝나지 않는다 — 조금씩만 민다.
        repeat(2) {
            h.app.sceneDidBecomeActive()
            advanceTimeBy(1_000)
            runCurrent()
            h.app.sceneDidEnterBackground()
            runCurrent()
        }
        h.app.sceneDidBecomeActive()
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(before, h.server.requests.count { it.rpcName == "client_release" }, "앞으로 돌아올 때 client_release 를 또 불렀다")
        assertTrue(h.app.now.showsUpdateNotice)
    }

    /** 닫으면 내려가고, 재실행해도 닫힌 채다 — 더 새 빌드가 나오면 다시 뜬다. */
    @Test
    fun dismissSurvivesRelaunchUntilANewerBuild() = runTest {
        val first = launched(release(8))
        assertTrue(first.app.now.showsUpdateNotice)
        first.app.now.dismissUpdateNotice()
        assertFalse(first.app.now.showsUpdateNotice)
        assertEquals(8L, first.app.now.dismissedUpdateBuild)
        assertEquals(8L, first.prefs.getLong(NowStore.dismissedUpdateBuildKey))

        val same = launched(release(8), first.prefs.values.toMap())
        assertEquals(8L, same.app.session.latestBuild)
        assertEquals(8L, same.app.now.dismissedUpdateBuild)
        assertFalse(same.app.now.showsUpdateNotice, "재실행하니 닫은 안내가 다시 떴다")

        val newer = launched(release(9), first.prefs.values.toMap())
        assertEquals(9L, newer.app.session.latestBuild)
        assertTrue(newer.app.now.showsUpdateNotice, "더 새 빌드인데 옛 닫기 기록이 가렸다")
    }

    /** 로그아웃해도 닫기 기록은 남는다(앱 단위) — 최신 빌드도 실행 단위 값이라 사라지지 않는다. */
    @Test
    fun dismissSurvivesSignOut() = runTest {
        val h = launched(release(8))
        h.app.now.dismissUpdateNotice()
        h.app.session.signOut()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedOut, h.app.session.phase)
        assertEquals(8L, h.app.now.dismissedUpdateBuild, "로그아웃 사슬이 값을 비웠다")
        assertEquals(8L, h.prefs.getLong(NowStore.dismissedUpdateBuildKey), "로그아웃이 저장값을 지웠다")
        assertFalse(NowStore.dismissedUpdateBuildKey in SessionPrefsKeys.userScopedKeys)
        assertEquals(8L, h.app.session.latestBuild, "최신 빌드는 실행 단위 값이라 로그아웃으로 사라지지 않는다")
        assertFalse(h.app.now.showsUpdateNotice)
    }

    @Test
    fun dismissWithoutAValueWritesNothing() = runTest {
        val h = launched(Reply.missingFunction)
        h.app.now.dismissUpdateNotice()
        assertNull(h.app.now.dismissedUpdateBuild)
        assertNull(h.prefs.getLong(NowStore.dismissedUpdateBuildKey))
    }
}
