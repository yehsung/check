// W2-h1 — 스토어(주기·입구 게이트·스냅숏·영속)와 파일 동작(쓰기 핸들이 열린 파일 읽기 · 캐시 왕복 · 입력 캐시 불변).
// 원본 규약: Sources/CheckCore/CheckTokenUsage.swift:1996-2341 — ★ INV-CheckTokenUsage-b93282d9(허용 게이트 = 스캔의 유일한 입구).
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.FileTime
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TokenUsageStoreTest {
    private val now = 1_792_033_200.0   // 2026-10-15T03:00:00Z
    private val home: Path = Files.createTempDirectory("token-store-home").toRealPath()
    private val appData: Path = Files.createTempDirectory("token-store-appdata").toRealPath()
    private val rollout = ".codex/sessions/2026/10/15/rollout-2026-10-15T00-00-00-0000000000s1.jsonl"

    @AfterTest fun cleanup() {
        home.toFile().deleteRecursively()
        appData.toFile().deleteRecursively()
    }

    private fun claude(id: String, out: Int) =
        """{"type":"assistant","timestamp":"2026-10-15T01:00:00.000Z","requestId":"r-$id","message":{"id":"$id","usage":{"input_tokens":10,"output_tokens":$out}}}""" + "\n"

    private fun tc(ts: String, i: Int, o: Int) =
        """{"timestamp":"$ts","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":$i,"output_tokens":$o,"cached_input_tokens":0}}}}""" + "\n"

    private fun put(rel: String, text: String, mtime: Long = now.toLong() - 600) {
        val p = TokenScanGoldenSupport.resolve(home, rel)
        Files.createDirectories(p.parent)
        Files.writeString(p, text)
        Files.setLastModifiedTime(p, FileTime.fromMillis(mtime * 1000))
    }

    private fun store(
        kv: InMemoryDesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
        clock: () -> SwiftDate = { SwiftDate(now) },
        permitted: () -> Boolean = { true },
        base: Path? = appData.resolve("token-usage-cache.json"),
    ) = TokenUsageStore(DesktopAiHomes.synthetic(home), kv, base, clock, permitted, Dispatchers.Unconfined)

    @Test fun permitGateIsTheOnlyEntrance_b93282d9() = runTest {
        put(".claude/projects/-s/a.jsonl", claude("a", 5))
        val kv = InMemoryDesktopKeyValueStore()
        val s = store(kv = kv, permitted = { false })
        s.refreshNow()
        s.refreshIfStale()
        s.persistForTermination()
        assertEquals(0, s.scanCount)
        assertNull(s.currentMonthUsage.value)
        assertTrue(kv.snapshot().isEmpty())
        assertFalse(Files.exists(TokenUsageCacheStore.stateFile(appData.resolve("token-usage-cache.json"))))
    }

    @Test fun snapshotRestoresOnlyInTheSameKstMonth() {
        val same = TokenUsageMonthly(month = "2026-10", claudeInput = 5)
        val old = TokenUsageMonthly(month = "2026-09", claudeInput = 5)
        assertEquals(same, store(kv = InMemoryDesktopKeyValueStore(mapOf(TokenUsageStore.SNAPSHOT_KEY to same.encode()))).currentMonthUsage.value)
        assertNull(store(kv = InMemoryDesktopKeyValueStore(mapOf(TokenUsageStore.SNAPSHOT_KEY to old.encode()))).currentMonthUsage.value)
    }

    @Test fun refreshIfStaleSkipsWithinThreeSecondsAndSnapshotsOnlyNonZero() = runTest {
        var t = now
        val kv = InMemoryDesktopKeyValueStore()
        val s = store(kv = kv, clock = { SwiftDate(t) })
        s.refreshIfStale()
        assertEquals(1, s.scanCount)
        assertEquals(0, s.currentMonthUsage.value!!.total)
        assertNull(kv.getString(TokenUsageStore.SNAPSHOT_KEY), "빈 집계는 스냅숏을 덮지 않는다")
        put(".claude/projects/-s/a.jsonl", claude("a", 5))
        t += 2.9
        s.refreshIfStale()
        assertEquals(1, s.scanCount)
        t += 0.2
        s.refreshIfStale()
        assertEquals(2, s.scanCount)
        assertEquals(15, s.currentMonthUsage.value!!.total)
        assertEquals(15, TokenUsageMonthly.decode(kv.getString(TokenUsageStore.SNAPSHOT_KEY)!!).total)
    }

    @Test fun cachePersistsOnTerminationAndReloadsWithoutRereading() = runTest {
        put(".claude/projects/-s/a.jsonl", claude("a", 5))
        put(rollout, tc("2026-10-15T00:00:01.000Z", 100, 10) + tc("2026-10-15T00:05:00.000Z", 160, 16))
        val base = appData.resolve("token-usage-cache.json")
        val s = store(base = base)
        s.refreshNow()
        assertEquals(0, s.saveCount, "생성 직후 스캔은 5분 저장 스로틀(lastSaveAt = 생성 시각) 안 — 아직 쓰지 않는다")
        assertFalse(Files.exists(TokenUsageCacheStore.stateFile(base)))
        s.persistForTermination()
        assertEquals(1, s.saveCount)
        val loaded = TokenUsageCacheStore.load(base)
        val again = TokenUsageIncrementalScanner.update(loaded, DesktopAiHomes.synthetic(home), SwiftDate(now))
        assertEquals(0, again.stats.claudeFilesRead + again.stats.codexFilesRead, "size·mtime 이 같으면 재읽기 0")
        assertEquals(s.currentMonthUsage.value, again.usage)
        assertEquals(66, again.usage.codexInput + again.usage.codexOutput)
    }

    @Test fun updateNeverMutatesItsInputCache() {
        put(".claude/projects/-s/a.jsonl", claude("a", 5))
        val input = TokenUsageCache()
        val r = TokenUsageIncrementalScanner.update(input, DesktopAiHomes.synthetic(home), SwiftDate(now))
        assertTrue(input.claudeEntries.isEmpty() && input.claudeFileStates.isEmpty())
        assertEquals(1, r.cache.claudeEntries.size)
    }

    @Test fun cacheCodecRoundTripsAndSchemaGateDropsOnlyCodex() {
        put(".claude/projects/-s/a.jsonl", claude("a", 5))
        put(rollout, tc("2026-10-15T00:00:01.000Z", 100, 10) + tc("2026-10-15T00:05:00.000Z", 160, 16))
        val cache = TokenUsageIncrementalScanner.update(TokenUsageCache(), DesktopAiHomes.synthetic(home), SwiftDate(now)).cache
        val base = appData.resolve("c.json")
        assertTrue(TokenUsageCacheStore.save(cache, setOf(TokenUsageCacheStore.Part.STATE), base))
        assertEquals(cache, TokenUsageCacheStore.load(base), "한쪽만 요청해도 없는 짝 파일은 같이 쓴다")
        val state = TokenUsageCacheStore.encodeState(cache)
        val oldSchema = kotlinx.serialization.json.JsonObject(state + ("codexSchemaVersion" to kotlinx.serialization.json.JsonPrimitive(4)))
        val decoded = TokenUsageCacheStore.decodeState(oldSchema)
        assertTrue(decoded.codexFileStates.isEmpty() && decoded.claudeFileStates == cache.claudeFileStates)
        Files.writeString(TokenUsageCacheStore.entriesFile(base), """{"not-hex":[1,2,3,4,5]}""")
        assertTrue(TokenUsageCacheStore.load(base).claudeFileStates.isEmpty(), "엔트리 파일이 상하면 통째로 버린다")
        // 키 정의: SHA-256("id\0req") 앞 16바이트 == 옛 문자열 키 해시.
        assertEquals(ClaudeEntryKey.of("msg", "req"), ClaudeEntryKey.ofDedupeString("msg\u0000req"))
        assertEquals(ClaudeEntryKey.of("msg", "req"), ClaudeEntryKey.fromHex(ClaudeEntryKey.of("msg", "req").hex.uppercase()))
    }

    /** Windows 러너 몫: 다른 핸들이 쓰기로 연 채(덧쓰는 중) 스캔해도 읽히고, 덧붙인 뒤 이어 읽는다. */
    @Test fun scansAFileHeldOpenForWritingByAnotherHandle() {
        val p = TokenScanGoldenSupport.resolve(home, rollout)
        Files.createDirectories(p.parent)
        FileChannel.open(p, StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.APPEND).use { w ->
            w.write(ByteBuffer.wrap((tc("2026-10-15T00:00:01.000Z", 100, 10) + tc("2026-10-15T00:05:00.000Z", 160, 16)).toByteArray()))
            w.force(true)
            Files.setLastModifiedTime(p, FileTime.fromMillis((now.toLong() - 600) * 1000))
            val first = TokenUsageIncrementalScanner.update(TokenUsageCache(), DesktopAiHomes.synthetic(home), SwiftDate(now))
            assertEquals(66, first.usage.codexInput + first.usage.codexOutput)
            w.write(ByteBuffer.wrap(tc("2026-10-15T00:06:00.000Z", 200, 20).toByteArray()))
            w.force(true)
            Files.setLastModifiedTime(p, FileTime.fromMillis((now.toLong() - 300) * 1000))
            val second = TokenUsageIncrementalScanner.update(first.cache, DesktopAiHomes.synthetic(home), SwiftDate(now))
            assertEquals(110, second.usage.codexInput + second.usage.codexOutput)
            assertEquals(tc("2026-10-15T00:06:00.000Z", 200, 20).toByteArray().size.toLong(), second.stats.codexBytesRead)
        }
    }
}
