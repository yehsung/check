// 조정자 핀 시험(xplat-w2/pins.md A·C·D) — 갈래는 읽기만. 핀의 최소 구현이 Swift 원본 산식과 같은지 잰다.
package com.yehsung.aingcheck.feature.desktop

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PinContractsTest {
    /** Swift CheckTokenUsage.swift:180-189 CodingKeys(프로퍼티 이름 그대로) — 순서까지 Swift encode(to:) 와 같다. */
    private val swiftKeys = listOf(
        "month", "claudeInput", "claudeOutput", "claudeCacheRead", "claudeCacheCreation",
        "codexInput", "codexOutput", "codexCacheRead",
        "antigravityInput", "antigravityOutput", "antigravityThinking", "antigravityCacheRead",
        "todayTotal", "todayDate", "claudeDaily", "codexDaily", "codexDailyUTC", "antigravityDaily",
        "windowStart", "claudeCompleteFrom",
    )

    @Test
    fun tokenUsageMonthlyKeysAreSwiftPropertyNames() {
        val encoded = Json.parseToJsonElement(TokenUsageMonthly(month = "2026-10").encode()).jsonObject
        assertEquals(swiftKeys, encoded.keys.toList(), "인코드는 언제나 Swift 키 20개 전부(encodeDefaults)")
    }

    @Test
    fun tokenUsageMonthlyDecodeIfPresentFallbacks() {
        // Swift decodeIfPresent: month 만 필수, 옛 스냅샷의 빠진 키는 0·""·빈 맵. 모르는 키는 무시.
        val old = TokenUsageMonthly.decode("""{"month":"2026-10","claudeInput":3000000000,"future":1}""")
        assertEquals(TokenUsageMonthly(month = "2026-10", claudeInput = 3_000_000_000L), old)
        assertEquals("2026-10-01", old.windowStartDay)
        assertEquals("2026-10-07", old.copy(windowStart = "2026-10-07").windowStartDay)
    }

    @Test
    fun tokenUsageMonthlyTotalsMatchSwift() {
        val u = TokenUsageMonthly(
            month = "2026-10", claudeInput = 1, claudeOutput = 2, claudeCacheRead = 4, claudeCacheCreation = 8,
            codexInput = 16, codexOutput = 32, codexCacheRead = 64,
            antigravityInput = 128, antigravityOutput = 256, antigravityThinking = 512, antigravityCacheRead = 1024,
            codexDaily = mapOf("2026-10-30" to 5L),
        )
        // ★ Swift total 은 codexCacheRead·안티그래비티를 빼고 더한다(CheckTokenUsage.swift:80-82).
        assertEquals(1L + 2 + 4 + 8 + 16 + 32, u.total)
        assertEquals(15L, u.claudeTotal)
        assertEquals(48L, u.codexTotal)
        assertEquals(1920L, u.antigravityTotal)
        assertEquals(mapOf("2026-10-30" to 5L), u.codexDailyOnAccountAxis, "UTC 맵이 비면 KST 맵으로 후퇴")
        assertEquals(mapOf("2026-10-29" to 7L), u.copy(codexDailyUTC = mapOf("2026-10-29" to 7L)).codexDailyOnAccountAxis)
    }

    @Test
    fun desktopAppConfigDefaultsTable() {
        val c = DesktopAppConfig()
        val table = mapOf(
            "duels" to c.duels, "poke" to c.poke, "ultra" to c.ultra, "chatToast" to c.chatToast, "forkSafe" to c.forkSafe,
            "tokenUpload" to c.tokenUpload, "adoptedPokeConsume" to c.adoptedPokeConsume, "spectator" to c.spectator,
        )
        // W-3 #17: 전부 꺼짐, 관전만 켬(W-3 #4).
        assertEquals(mapOf("duels" to false, "poke" to false, "ultra" to false, "chatToast" to false, "forkSafe" to false,
            "tokenUpload" to false, "adoptedPokeConsume" to false, "spectator" to true), table)
        assertEquals(false, c.toAppConfig().duelsEnabled)
        assertEquals(true, c.copy(duels = true).toAppConfig().duelsEnabled)
    }

    @Test
    fun todaySecondsClipsAtKstMidnightLikeSwift() {
        val now = SwiftDate(1_793_000_000.0)
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        val sinceMidnight = now.timeIntervalSince(dayStart).toLong()
        // 어제 스탬프의 누적은 세지 않는다 · 자정 전 시작한 세션은 자정부터만 센다.
        val crossing = DesktopWorkSnapshot(isWorking = true, startedAt = dayStart.addingTimeInterval(-3600.0),
            accumulatedTodaySeconds = 999, accumulatedDayStart = dayStart.addingTimeInterval(-1.0))
        assertEquals(sinceMidnight, crossing.todaySeconds(now))
        assertEquals(sinceMidnight + 3600, crossing.elapsedSeconds(now))
        // 오늘 스탬프의 누적은 더한다 · 근무 중이 아니면 누적만.
        val idle = DesktopWorkSnapshot(accumulatedTodaySeconds = 120, accumulatedDayStart = dayStart)
        assertEquals(120L, idle.todaySeconds(now))
        assertEquals(0L, idle.elapsedSeconds(now))
        // 시계 되돌림 음수는 0.
        val future = DesktopWorkSnapshot(isWorking = true, startedAt = now.addingTimeInterval(10.0))
        assertEquals(0L, future.todaySeconds(now))
        assertEquals(0L, future.elapsedSeconds(now))
    }

    @Test
    fun keyValueStoreAndIds() {
        val kv = InMemoryDesktopKeyValueStore()
        kv.putLong("work.queue.gen", 3)
        kv.putBoolean("overlay.on", true)
        kv.putString("work.owner", "abc")
        assertEquals(3L, kv.getLong("work.queue.gen"))
        assertEquals(true, kv.getBoolean("overlay.on"))
        assertEquals(listOf("work.owner", "work.queue.gen"), kv.keys("work."))
        kv.remove("work.owner")
        assertNull(kv.getString("work.owner"))
        assertEquals("ab-cd", WorkSessionIds.canonical("AB-cd"))
        assertNull(WorkSessionIds.canonical(null))
        val homes = DesktopAiHomes.synthetic(Path.of("/synthetic-home"))
        assertEquals(Path.of("/synthetic-home/.claude"), homes.claudeDir())
        assertEquals(Path.of("/synthetic-home/.codex"), homes.codexHome())
    }
}
