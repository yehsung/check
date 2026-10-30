// W3-c5 완료 기준: 목 엔진 본문 {"p_platform":"windows"} — client_release · app_current_notice_for 두 RPC 만(⑦), 공지 null 규칙.
// 원본: SupabaseWorkService.swift 1247-1265(비2xx = 공지 없음, `{}` 디코드 실패 = nil) · 20261101100000/20261101120000 마이그레이션 응답 모양.
// MockRouter 는 등록 안 된 요청(app_latest_release·app_current_notice 포함)을 실패로 남긴다 — 끝마다 assertAllRouted.
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.testkit.mock.MockRouter
import com.yehsung.aingcheck.testkit.mock.StubResponse
import kotlinx.coroutines.test.runTest
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UpdateRpcTest {
    private val windowsBody = """{"p_platform":"windows"}"""
    private val fullRelease = """{"status":"ok","platform":"windows","min_build":3,"latest_build":12,"notes":"고친 점",""" +
        """"latest_version":"0.4.2","download_url":"https://example.invalid/aing-check-0.4.2.msix","updated_at":"2026-10-30T00:00:00+00:00"}"""

    @Test
    fun clientReleaseSendsWindowsPlatformAndDecodesExtraFields() = runTest {
        val router = MockRouter().rpc("client_release", StubResponse.Json(fullRelease))
        val r = ServiceUpdateRpc(stubService(router), "windows").clientRelease()
        router.assertAllRouted()
        val req = router.requests.single()
        assertEquals("POST", req.method)
        assertEquals("/rest/v1/rpc/client_release", req.path)
        assertEquals(windowsBody, req.bodyText)
        assertEquals(listOf("Bearer $STUB_ANON"), req.headers["Authorization"], "anon — 로그인 전에도 돈다")
        assertEquals(
            ClientReleaseResponse("ok", "windows", 3, 12, "고친 점", "0.4.2", "https://example.invalid/aing-check-0.4.2.msix", "2026-10-30T00:00:00+00:00"),
            r,
        )
    }

    @Test
    fun unknownPlatformDecodesToNoLatest() = runTest {
        val router = MockRouter().rpc("client_release", StubResponse.Json("""{"status":"unknown_platform"}"""))
        val r = ServiceUpdateRpc(stubService(router), "windows").clientRelease()
        assertEquals(ClientReleaseResponse(status = "unknown_platform"), r)
    }

    @Test
    fun noticeForSendsWindowsPlatformAndTrims() = runTest {
        val router = MockRouter().rpc(
            "app_current_notice_for",
            StubResponse.Json("""{"v":1,"id":"win-1","title":"  점검 안내 ","body":"오늘 밤","link_url":"","link_label":null}"""),
        )
        val n = ServiceUpdateRpc(stubService(router), "windows").currentNotice()
        router.assertAllRouted()
        val req = router.requests.single()
        assertEquals("/rest/v1/rpc/app_current_notice_for", req.path)
        assertEquals(windowsBody, req.bodyText)
        assertEquals(AppNotice(id = "win-1", title = "점검 안내", body = "오늘 밤", linkURL = null, linkLabel = null), n)
    }

    @Test
    fun noticeNullRules() = runTest {
        // `{}` = 공지 없음 · 옛 서버(PGRST202 404) · 5xx · anon 키 없음 → null.
        for (resp in listOf(StubResponse.Json("{}"), StubResponse.missingFunction("app_current_notice_for"), StubResponse.Json("""{"message":"x"}""", 503))) {
            val router = MockRouter().rpc("app_current_notice_for", resp)
            assertNull(ServiceUpdateRpc(stubService(router), "windows").currentNotice(), "응답 $resp")
            router.assertAllRouted()
        }
        assertNull(ServiceUpdateRpc(stubService(MockRouter(), anonKey = null), "windows").currentNotice())
    }

    @Test
    fun noticeTransportFailureThrows() = runTest {
        val router = MockRouter().rpc("app_current_notice_for", StubResponse.TransportFailure())
        assertFailsWith<IOException> { ServiceUpdateRpc(stubService(router), "windows").currentNotice() }
    }

    @Test
    fun checkerOverServiceCallsOnlyTheTwoWindowsRpcsInOrder() = runTest {
        val router = MockRouter()
            .rpc("client_release", StubResponse.Json(fullRelease))
            .rpc("app_current_notice_for", StubResponse.Json("""{"v":1,"id":"win-2","title":"T","body":"B"}"""))
        val c = DesktopUpdateChecker(ServiceUpdateRpc(stubService(router), "windows"), 11, InMemoryDesktopKeyValueStore(), backgroundScope, virtualMonotonic(testScheduler))
        c.checkNow()
        router.assertAllRouted()
        assertEquals(listOf("/rest/v1/rpc/client_release", "/rest/v1/rpc/app_current_notice_for"), router.requests.map { it.path }, "★1 릴리스 뒤 공지")
        assertTrue(router.requests.all { it.bodyText == windowsBody })
        assertTrue(c.state.value.updateAvailable)
        assertEquals("win-2", c.state.value.notice?.id)
    }
}
