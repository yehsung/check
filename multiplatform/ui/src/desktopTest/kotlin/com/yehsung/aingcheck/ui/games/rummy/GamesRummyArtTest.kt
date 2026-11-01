// 원본: Tests/checkTests/V0369RummyV2MatchTests.swift 의 뜻(캐시 → 번들 → 폴백 · 조건부 요청 표) — 받기·디스크를 가짜로 바꿔 값으로 잰다(망 0).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.rules.rummy.RummyArtKind
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

private val rackImage = ImageBitmap(1600, 319)
private val tableImage = ImageBitmap(512, 512)
private val newRack = ImageBitmap(2400, 478)
private val tooSmall = ImageBitmap(100, 100)
private val joker = ImageBitmap(192, 192)

/** 바이트 첫 값으로 그림을 고르는 가짜 디코더(1 = 번들급 받침대 · 2 = 펠트 · 3 = 새 받침대 · 4 = 못 쓰는 그림 · 그 밖 = 못 읽음). */
private fun fakeDecode(bytes: ByteArray): ImageBitmap? = when (bytes.firstOrNull()?.toInt()) {
    1 -> rackImage
    2 -> tableImage
    3 -> newRack
    4 -> tooSmall
    else -> null
}

private class FakeSource(
    val cache: MutableMap<RummyArtKind, ByteArray> = mutableMapOf(),
    val replies: MutableMap<RummyArtKind, GamesRummyArtResponse?> = mutableMapOf(),
) : GamesRummyArtSource {
    val validators = mutableMapOf<RummyArtKind, GamesRummyArtValidators>()
    val sent = mutableListOf<Pair<RummyArtKind, GamesRummyArtValidators?>>()
    val cleared = mutableListOf<RummyArtKind>()

    override suspend fun readCached(kind: RummyArtKind): ByteArray? = cache[kind]
    override suspend fun readValidators(kind: RummyArtKind): GamesRummyArtValidators? = validators[kind]
    override suspend fun fetch(kind: RummyArtKind, validators: GamesRummyArtValidators?): GamesRummyArtResponse? {
        sent += kind to validators
        return replies[kind]
    }
    override suspend fun writeCache(kind: RummyArtKind, bytes: ByteArray, validators: GamesRummyArtValidators) {
        cache[kind] = bytes
        this.validators[kind] = validators
    }
    override suspend fun clearCache(kind: RummyArtKind) {
        cache.remove(kind)
        cleared += kind
    }
}

private fun art(source: GamesRummyArtSource?, bundle: Boolean = true) = GamesRummyArt(
    source,
    decode = { fakeDecode(it) },
    bundled = { kind -> if (!bundle) null else if (kind == RummyArtKind.rack) rackImage else tableImage },
    jokerFace = { joker },
)

class GamesRummyArtTest {
    @Test
    fun cacheBeatsBundleAndBadCacheFallsBack() = runBlocking {
        val source = FakeSource(cache = mutableMapOf(RummyArtKind.rack to byteArrayOf(3), RummyArtKind.table to byteArrayOf(4)))
        val store = art(source)
        store.prepare()
        assertSame(newRack, store.rack, "캐시가 번들보다 먼저")
        assertSame(tableImage, store.table, "못 쓰는 캐시는 번들로")
        assertSame(joker, store.joker)
    }

    @Test
    fun nothingLeavesNullSoTheScreenDrawsTheFallback() = runBlocking {
        val store = art(null, bundle = false)
        store.prepare()
        assertNull(store.rack)
        assertNull(store.table)
        // ★ 망·디스크가 없는 조립(시험·스냅숏)은 받기를 시도하지 않는다.
        store.refreshIfNeeded()
        assertNull(store.rack)
    }

    @Test
    fun conditionalRequestCarriesValidatorsOnlyWithACache() = runBlocking {
        val withCache = FakeSource(cache = mutableMapOf(RummyArtKind.rack to byteArrayOf(1)))
        withCache.validators[RummyArtKind.rack] = GamesRummyArtValidators("e1", "m1")
        art(withCache).refreshIfNeeded()
        assertEquals(GamesRummyArtValidators("e1", "m1"), withCache.sent.first { it.first == RummyArtKind.rack }.second)
        // 캐시 없이 메타만 남았으면 조건 없이 받는다 — 304 를 받아도 올릴 그림이 없다.
        val orphan = FakeSource()
        orphan.validators[RummyArtKind.rack] = GamesRummyArtValidators("e1", "m1")
        art(orphan).refreshIfNeeded()
        assertNull(orphan.sent.first { it.first == RummyArtKind.rack }.second)
    }

    @Test
    fun replaceWritesCacheAndSwapsTheImage() = runBlocking {
        val source = FakeSource(replies = mutableMapOf(RummyArtKind.rack to GamesRummyArtResponse(200, byteArrayOf(3), "e2", "m2")))
        val store = art(source)
        store.prepare()
        store.refreshIfNeeded()
        assertSame(newRack, store.rack)
        assertEquals(3, assertNotNull(source.cache[RummyArtKind.rack])[0].toInt())
        assertEquals(GamesRummyArtValidators("e2", "m2"), source.validators[RummyArtKind.rack])
    }

    @Test
    fun keepLeavesEverythingAlone() = runBlocking {
        for (reply in listOf(
            GamesRummyArtResponse(304, ByteArray(0), null, null),
            GamesRummyArtResponse(500, ByteArray(0), null, null),
            GamesRummyArtResponse(200, byteArrayOf(4), "x", "y"),
            GamesRummyArtResponse(200, byteArrayOf(9), "x", "y"),
            null,
        )) {
            val source = FakeSource(cache = mutableMapOf(RummyArtKind.rack to byteArrayOf(1)), replies = mutableMapOf(RummyArtKind.rack to reply))
            val store = art(source)
            store.prepare()
            store.refreshIfNeeded()
            assertSame(rackImage, store.rack)
            assertEquals(1, source.cache[RummyArtKind.rack]?.get(0)?.toInt(), "캐시를 덮었다")
            assertTrue(source.cleared.isEmpty())
        }
    }

    @Test
    fun notFoundRevertsToBundle() = runBlocking {
        val source = FakeSource(
            cache = mutableMapOf(RummyArtKind.rack to byteArrayOf(3)),
            replies = mutableMapOf(RummyArtKind.rack to GamesRummyArtResponse(404, ByteArray(0), null, null)),
        )
        val store = art(source)
        store.prepare()
        assertSame(newRack, store.rack)
        store.refreshIfNeeded()
        assertSame(rackImage, store.rack, "지워졌으면 번들로")
        assertEquals(listOf(RummyArtKind.rack), source.cleared)
    }

    @Test
    fun refreshRunsOncePerApp() = runBlocking {
        val source = FakeSource()
        val store = art(source)
        store.refreshIfNeeded()
        val first = source.sent.size
        assertEquals(RummyArtKind.entries.size, first)
        store.refreshIfNeeded()
        assertEquals(first, source.sent.size, "화면을 열 때마다 받지 않는다")
    }

    @Test
    fun bundlePathsAreWhereGradleSyncPutsThem() {
        assertEquals("files/art/rummy-rack.png", GamesRummyArt.bundlePath(RummyArtKind.rack))
        assertEquals("files/art/rummy-table.png", GamesRummyArt.bundlePath(RummyArtKind.table))
    }
}
