// 원본: 없음 — `client_release` 가 마이그레이션 20261101100000 부터 더 주는 세 칸(latest_version·download_url·updated_at)은 Swift 에 없다.
//   Swift 골든을 지어내지 않고 옛 응답(다섯 칸)·새 응답(여덟 칸)을 합성 JSON 으로 잰다. 픽스처는 전부 합성이다.
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ClientReleaseResponseDecodeTest {
    private fun decode(json: String): ClientReleaseResponse = SwiftJson.decode(ClientReleaseResponse.serializer(), json)

    private val old = """{"status":"ok","platform":"windows","min_build":3,"latest_build":5,"notes":"합성 노트"}"""
    private val new = """{"status":"ok","platform":"windows","min_build":3,"latest_build":5,"notes":"합성 노트",""" +
        """"latest_version":"0.1.5","download_url":"https://example.invalid/aing-check-setup.exe","updated_at":"2026-11-01T03:04:05.678+00:00"}"""

    /** 옛 서버(세 칸 없음): 앞 다섯 칸은 그대로, 새 세 칸은 null. */
    @Test
    fun oldResponseDecodesWithNullExtras() {
        val r = decode(old)
        assertEquals(ClientReleaseResponse("ok", "windows", 3, 5, "합성 노트"), r)
        assertNull(r.latestVersion)
        assertNull(r.downloadUrl)
        assertNull(r.updatedAt)
    }

    /** 새 서버: 세 칸을 서버 키 그대로 읽는다. 시각은 원문 문자열(이 파일의 다른 서버 시각 칸과 같다). */
    @Test
    fun newResponseDecodesTheExtras() {
        val r = decode(new)
        assertEquals("0.1.5", r.latestVersion)
        assertEquals("https://example.invalid/aing-check-setup.exe", r.downloadUrl)
        assertEquals("2026-11-01T03:04:05.678+00:00", r.updatedAt)
        assertEquals(decode(old), r.copy(latestVersion = null, downloadUrl = null, updatedAt = null), "앞 다섯 칸은 옛 응답과 같다")
    }

    /** 서버가 세 칸을 null 로 줄 때(씨앗 행 · 아직 안 채운 플랫폼)와 모르는 플랫폼(`{"status":"unknown_platform"}`). */
    @Test
    fun nullExtrasAndUnknownPlatform() {
        val nulls = decode("""{"status":"ok","platform":"android","min_build":1,"latest_build":1,"notes":null,"latest_version":null,"download_url":null,"updated_at":null}""")
        assertEquals(ClientReleaseResponse("ok", "android", 1, 1, null), nulls)
        assertEquals(ClientReleaseResponse(status = "unknown_platform"), decode("""{"status":"unknown_platform"}"""))
    }

    /** Swift 덤프와 맞추는 투영(골든 시험)은 **세 칸만** 뺀다 — 새 응답의 투영이 옛 응답의 덤프와 같다. */
    @Test
    fun swiftShapeDropsOnlyTheThreeKotlinOnlyFields() {
        val shaped = WireDecodeGoldenTest.swiftShape(decode(new))
        assertEquals(setOf("status", "platform", "minBuild", "latestBuild", "notes"), (shaped as kotlinx.serialization.json.JsonObject).keys)
        assertEquals(GoldenCanonical.text(WireDecodeGoldenTest.swiftShape(decode(old))), GoldenCanonical.text(shaped))
    }
}
