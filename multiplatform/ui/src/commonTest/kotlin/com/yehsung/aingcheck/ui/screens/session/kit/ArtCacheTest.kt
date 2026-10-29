// 원본: 없음 — 그림 캐시 규칙(6차 int-h 이월 '그림 캐시'): 같은 열쇠 동시 요청 1회 · 실패 기억 · LRU 상한 · 취소는 실패가 아니다.
package com.yehsung.aingcheck.ui.screens.session.kit

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ArtCacheTest {
    @Test
    fun concurrentRequestsForOneKeyLoadOnce() = runTest {
        val gate = CompletableDeferred<Unit>()
        val calls = mutableListOf<String>()
        val cache = ArtCache<String>(capacity = 8) { key -> calls += key; gate.await(); "img:$key" }
        val ten = List(10) { async { cache.get("fox") } }
        yield()
        gate.complete(Unit)
        assertEquals(List(10) { "img:fox" }, ten.awaitAll())
        assertEquals(listOf("fox"), calls, "목록 열 줄이 같은 초상을 청했는데 디코드가 여러 번 돌았다")
        assertEquals(1, cache.loadCount)
        // 이미 든 값은 다시 부르지 않는다(다시 그리기 · 스크롤).
        assertEquals("img:fox", cache.peek("fox"))
        assertEquals("img:fox", cache.get("fox"))
        assertEquals(1, cache.loadCount)
    }

    @Test
    fun failuresAreRememberedAndNotRetried() = runTest {
        var calls = 0
        val cache = ArtCache<String>(capacity = 8) { key -> calls += 1; if (key == "broken") null else error("boom") }
        assertNull(cache.get("broken"))
        assertNull(cache.get("throws"))
        assertTrue(cache.hasFailed("broken"))
        assertTrue(cache.hasFailed("throws"))
        // 오프라인에서 줄마다 사진 요청이 쌓이지 않게 — 다시 묻지 않는다.
        assertNull(cache.get("broken"))
        assertEquals(2, calls)
    }

    @Test
    fun leastRecentlyUsedIsEvictedAtCapacity() = runTest {
        val cache = ArtCache<String>(capacity = 2) { "v:$it" }
        cache.get("a")
        cache.get("b")
        cache.get("a") // a 를 최근으로
        cache.get("c") // b 가 나간다
        assertEquals("v:a", cache.peek("a"))
        assertNull(cache.peek("b"))
        assertEquals("v:c", cache.peek("c"))
        assertEquals(2, cache.size)
    }

    @Test
    fun cancellationIsNotAFailure() = runTest {
        val gate = CompletableDeferred<Unit>()
        var calls = 0
        val cache = ArtCache<String>(capacity = 4) { key -> calls += 1; if (calls == 1) gate.await(); "v:$key" }
        val first = launch { cache.get("k") }
        yield()
        first.cancel(CancellationException("화면이 사라졌다"))
        first.join()
        assertFalse(cache.hasFailed("k"), "취소를 실패로 기억하면 그 그림은 다시 열어도 영영 안 나온다")
        assertEquals("v:k", cache.get("k"))
        assertEquals(2, calls)
    }
}
