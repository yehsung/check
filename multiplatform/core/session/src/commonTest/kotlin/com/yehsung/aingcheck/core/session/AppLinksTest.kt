// 원본: Tests/CheckMobileKitTests/BaseSessionTests.swift:460-488(업데이트 화면은 스토어로 — 막다른 스킴 금지) · Sources/CheckCore/CheckAppLinks.swift @ 1b8260d
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import io.ktor.http.Url
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AppLinksTest {
    /**
     * INV-MobileSessionStore-cc0d4cc0 · a846909f · 68eea3ec 의 Android 몫: 업데이트 목적지는 https(market:// 아님 — Play 앱이 없으면 무반응),
     * 호스트 play.google.com, 경로 /store/apps/details, 쿼리는 앱 id 하나(hl·gl 없음).
     */
    @Test
    fun playStoreDestinationIsHttpsWithoutLocaleTail() {
        val url = Url(AppLinks.updateDestination(ClientPlatform.ANDROID)!!)
        assertEquals("https", url.protocol.name)
        assertEquals("play.google.com", url.host)
        assertEquals("/store/apps/details", url.encodedPath)
        assertEquals(setOf("id"), url.parameters.names(), "지역·언어 꼬리 없음")
        assertEquals(AppLinks.androidApplicationId, url.parameters["id"])
        assertNull(AppLinks.updateDestination(ClientPlatform.WINDOWS), "Windows 는 보류 — 서버 download_url 을 읽는 갈래가 정한다")
        assertEquals("Play 스토어 열기", SessionText.updateButton(ClientPlatform.ANDROID))
        assertNull(SessionText.updateButton(ClientPlatform.WINDOWS))
    }

    /** INV-MobileSessionStore-f754b3e3 의 Android 몫: Play 주소의 앱 id 는 빌드가 쓰는 applicationId 와 같은 글자다(한 곳이 바뀌면 빨강). */
    @Test
    fun applicationIdMatchesTheAndroidBuild() {
        val build = RepoFiles.readText("multiplatform/build-logic/src/main/kotlin/aingcheck.android-app.gradle.kts")
        val declared = Regex("""applicationId\s*=\s*"([^"]+)"""").find(build)?.groupValues?.get(1)
        assertEquals(AppLinks.androidApplicationId, declared)
        assertTrue(AppLinks.privacyPolicy.startsWith("https://") && AppLinks.termsOfService.startsWith("https://"))
    }
}
