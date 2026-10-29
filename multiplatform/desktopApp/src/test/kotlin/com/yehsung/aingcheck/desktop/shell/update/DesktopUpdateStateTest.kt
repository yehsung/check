// W3-c5 완료 기준: DesktopUpdateStateTest(latest>cur · 같음 · null) + 서버 결과 반영 규칙(★1·★3·⚠️5·⚠️6 — DesktopUpdateChecker 주석 번호).
// 원본: CheckUpdateCheck.swift 147-152(빌드를 알면 빌드로만 비교) · 319-345(릴리스 뒤 공지, 각자 삼킨다) · WorkTimerStore.swift 1029-1044.
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlinx.coroutines.test.runTest
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DesktopUpdateStateTest {
    private val ok11 = WindowsClientRelease(
        status = "ok", platform = "windows", minBuild = 1, latestBuild = 11, notes = "고친 점",
        latestVersion = "0.4.1", downloadUrl = "https://example.invalid/aing-check-0.4.1.msix",
    )

    @Test
    fun latestAboveCurrentIsUpdateWithFields() = runTest {
        val rpc = FakeUpdateRpc(release = { ok11 })
        val c = DesktopUpdateChecker(rpc, 10, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        assertFalse(c.state.value.updateAvailable, "조회 전엔 새 버전이 없다")
        c.checkNow()
        val s = c.state.value
        assertTrue(s.updateAvailable)
        assertEquals(10L, s.currentBuild)
        assertEquals(11L, s.latestBuild)
        assertEquals("0.4.1", s.latestVersion)
        assertEquals("고친 점", s.notes)
        assertEquals("https://example.invalid/aing-check-0.4.1.msix", s.downloadUrl)
    }

    @Test
    fun sameBuildIsNotUpdate() = runTest {
        val c = DesktopUpdateChecker(FakeUpdateRpc(release = { ok11 }), 11, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        c.checkNow()
        assertEquals(11L, c.state.value.latestBuild)
        assertFalse(c.state.value.updateAvailable, "같은 빌드는 새 버전이 아니다")
    }

    @Test
    fun nullLatestOrUnknownPlatformIsNotUpdate() = runTest {
        val rpc = FakeUpdateRpc(release = { ok11 })
        val c = DesktopUpdateChecker(rpc, 10, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        c.checkNow()
        assertTrue(c.state.value.updateAvailable)
        // 서버가 줄을 지웠다(unknown_platform) — 알려진 새 버전이 없다.
        rpc.release = { WindowsClientRelease(status = "unknown_platform") }
        c.checkNow()
        assertNull(c.state.value.latestBuild)
        assertNull(c.state.value.downloadUrl)
        assertFalse(c.state.value.updateAvailable)
        // "ok" 인데 latest_build 가 비었다.
        rpc.release = { WindowsClientRelease(status = "ok", latestBuild = null) }
        c.checkNow()
        assertFalse(c.state.value.updateAvailable)
    }

    @Test
    fun star3ReleaseFailureKeepsStateAndStar1DoesNotBlockNotice() = runTest {
        val rpc = FakeUpdateRpc(release = { ok11 }, notice = { notice("n1") })
        val c = DesktopUpdateChecker(rpc, 10, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        c.checkNow()
        rpc.release = { throw IOException("offline") }
        rpc.notice = { notice("n2") }
        c.checkNow()
        assertTrue(c.state.value.updateAvailable, "★3 던지면 모름 — 알던 새 버전을 지우지 않는다")
        assertEquals("n2", c.state.value.notice?.id, "★1 릴리스 실패가 공지를 막지 않는다")
        assertEquals(2, rpc.noticeCalls.size)
    }

    @Test
    fun warn5NoticeThrowKeepsCardNullClears() = runTest {
        val rpc = FakeUpdateRpc(notice = { notice("n1") })
        val c = DesktopUpdateChecker(rpc, 10, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        c.checkNow()
        assertEquals("n1", c.state.value.notice?.id)
        rpc.notice = { throw IOException("offline") }
        c.checkNow()
        assertEquals("n1", c.state.value.notice?.id, "⚠️5 던지면 떠 있던 카드를 그대로 둔다")
        rpc.notice = { null }
        c.checkNow()
        assertNull(c.state.value.notice, "null 은 결과 — 카드를 내린다")
    }

    @Test
    fun warn6DismissedIdStaysHiddenPerDeviceNewIdShows() = runTest {
        val store = InMemoryDesktopKeyValueStore()
        val rpc = FakeUpdateRpc(notice = { notice("spring-1") })
        val c = DesktopUpdateChecker(rpc, 10, store, backgroundScope, virtualMonotonic(testScheduler))
        c.dismissNotice() // 보이는 공지가 없으면 키를 남기지 않는다
        assertEquals(emptyMap(), store.snapshot())
        c.checkNow()
        c.dismissNotice()
        assertNull(c.state.value.notice)
        assertEquals(setOf("check.notice.dismissed.spring-1"), store.snapshot().keys, "맥과 같은 키, 사용자 id 없음")
        c.checkNow()
        assertNull(c.state.value.notice, "같은 id 는 다시 안 뜬다")
        // 재실행(새 조회기, 같은 기기 저장소)에도 닫힘이 남는다.
        val again = DesktopUpdateChecker(rpc, 10, store, backgroundScope, virtualMonotonic(testScheduler))
        again.checkNow()
        assertNull(again.state.value.notice)
        rpc.notice = { notice("spring-2") }
        again.checkNow()
        assertEquals("spring-2", again.state.value.notice?.id, "새 id 는 다시 뜬다")
    }
}
