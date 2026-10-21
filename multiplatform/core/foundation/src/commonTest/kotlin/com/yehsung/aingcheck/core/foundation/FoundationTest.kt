package com.yehsung.aingcheck.core.foundation

import com.yehsung.aingcheck.core.foundation.coroutines.tryOrNull
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.json.AingJson
import com.yehsung.aingcheck.core.foundation.time.KST
import kotlinx.coroutines.CancellationException
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.time.Instant

class FoundationTest {
    @Test
    fun tryOrNullFoldsFailuresButRethrowsCancellation() {
        assertNull(tryOrNull { error("boom") })
        assertEquals(3, tryOrNull { 3 })
        assertFailsWith<CancellationException> { tryOrNull { throw CancellationException("stop") } }
    }

    @Serializable
    private data class Probe(
        @SerialName("p_protocol") val protocol: Int = 2,
        @SerialName("p_note") val note: String? = null,
    )

    @Test
    fun wireJsonKeepsDefaultsDropsNullsIgnoresUnknownKeys() {
        // Swift 합성 Encodable 과 같은 바이트: 기본값은 싣고 nil 은 키째 뺀다.
        assertEquals("""{"p_protocol":2}""", AingJson.encodeToString(Probe.serializer(), Probe()))
        assertEquals(Probe(protocol = 3), AingJson.decodeFromString(Probe.serializer(), """{"p_protocol":3,"new_key":1}"""))
    }

    @Test
    fun clientIdentityRangesFollowEachPlatformAxis() {
        assertEquals(ClientIdentity(ClientPlatform.ANDROID, 1_000_000, "1.0.0"), ClientIdentity.fromGenerated("android", "1000000", "1.0.0"))
        assertFailsWith<IllegalArgumentException> { ClientIdentity(ClientPlatform.ANDROID, 1_000_001, "1.0.0") }
        assertFailsWith<IllegalArgumentException> { ClientIdentity(ClientPlatform.WINDOWS, 65_536, "1.0.65536") }
        assertFailsWith<IllegalArgumentException> { ClientIdentity.fromGenerated("mac", "1", "1.0") }
    }

    @Test
    fun kstIsUtcPlusNineWithoutDst() {
        // 2026-09-17 05:05Z = 14:05 KST(iOS 데모 기준 시각) · 1월에도 +9(서머타임 없음)
        assertEquals(LocalDateTime(2026, 9, 17, 14, 5), Instant.parse("2026-09-17T05:05:00Z").toLocalDateTime(KST))
        assertEquals(LocalDateTime(2027, 1, 4, 0, 0), Instant.parse("2027-01-03T15:00:00Z").toLocalDateTime(KST))
    }
}
