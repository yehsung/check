package com.yehsung.aingcheck.desktop.pages.aitokens

import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.token.TokenRowServerValue
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.scan.TokenUsageStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import java.nio.file.Files
import java.nio.file.attribute.FileTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** W-9 #3: 토큰 사용량 수집은 동의(tokenUsageCollect) 전 스캔 0. 홈은 합성 임시 폴더(실제 ~/.claude 를 읽지 않는다). */
class AiTokensConsentTest {
    private val now = SwiftDate.fromEpochMillis(1_792_022_400_000) // 2026-10-15T00:00:00Z

    @Test
    fun noScanBeforeConsentThenScanAfter() = runBlocking {
        val home = Files.createTempDirectory("c4-home")
        try {
            val project = Files.createDirectories(home.resolve(".claude/projects/p1"))
            val file = project.resolve("s1.jsonl")
            Files.writeString(
                file,
                """{"type":"assistant","timestamp":"2026-10-15T01:00:00.000Z","requestId":"r-1","message":{"id":"m1","usage":{"input_tokens":10,"output_tokens":5}}}""" + "\n",
            )
            Files.setLastModifiedTime(file, FileTime.fromMillis(1_792_026_000_000))
            val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
            val scan = TokenUsageStore(
                homes = DesktopAiHomes(home) { home.resolve(".codex") },
                keyValueStore = InMemoryDesktopKeyValueStore(),
                cacheBase = null,
                clock = { now },
                isScanPermitted = { settings.tokenUsageCollect.value },
                ioDispatcher = Dispatchers.IO,
            )
            scan.refreshNow()
            scan.refreshIfStale()
            assertNull(scan.lastScanAt, "동의 전인데 스캔이 돌았다")
            assertEquals(0, scan.lastScanFileCount)
            assertNull(scan.currentMonthUsage.value)

            settings.setTokenUsageCollect(true)
            scan.refreshNow()
            assertNotNull(scan.lastScanAt, "동의 뒤에도 스캔이 안 돈다")
            assertTrue(scan.lastScanFileCount >= 1)
            assertEquals(15L, scan.currentMonthUsage.value?.total)
        } finally {
            home.toFile().deleteRecursively()
        }
    }

    @Test
    fun pageShowsConsentCardBeforeConsentEvenWithServerRow() {
        val server = TokenRowServerValue("u1", "2026-10", 1_234_567, 1_000_000, 234_567, 0, null, 0.0)
        val local = TokenUsageMonthly(month = "2026-10", claudeInput = 100, claudeOutput = 20)
        assertEquals(AiTokensView.NeedsConsent, AiTokensModel.resolve(false, local, null, server, "u1", "2026-10"))

        val fromServer = assertIs<AiTokensView.Usage>(AiTokensModel.resolve(true, local, null, server, "u1", "2026-10"))
        assertEquals("1,234,567", fromServer.numberText)
        assertEquals(TokenNumberFormatter.grouped(1_234_567), fromServer.numberText)
        assertEquals("10월 AI 토큰 소모량", fromServer.titleText)
        assertTrue(fromServer.display.isFromServer)

        // 남의 행·지난달 행은 쓰지 않고 로컬로.
        val fromLocal = assertIs<AiTokensView.Usage>(AiTokensModel.resolve(true, local, null, server, "u2", "2026-10"))
        assertEquals("120", fromLocal.numberText)
        assertEquals(false, fromLocal.display.isFromServer)
        assertIs<AiTokensView.Usage>(AiTokensModel.resolve(true, local, null, server, "u1", "2026-11"))

        // 숫자가 하나도 없으면 순위 입구만(맥 boardEntryRow).
        assertEquals(AiTokensView.BoardOnly, AiTokensModel.resolve(true, TokenUsageMonthly(month = "2026-10"), null, null, "u1", "2026-10"))
        assertEquals(AiTokensView.BoardOnly, AiTokensModel.resolve(true, null, null, null, null, "2026-10"))
    }
}
