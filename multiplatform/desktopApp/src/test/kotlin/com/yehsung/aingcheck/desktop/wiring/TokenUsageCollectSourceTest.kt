// 원본: Sources/check/WorkTimerStorePoke.swift:841-856(받을 때까지 · 받으면 미러 + Loaded) · WorkTimerStore.swift:4112(로그아웃 리셋) · W-14 #10
@file:OptIn(ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TokenUsageCollectSourceTest {
    /** 받기 전 거짓 → 실패면 15초 뒤 다시 → 받으면 서버 값 · 계정 바뀌면 곧바로 거짓(앞 사람 값 0) · 로그아웃 거짓·요청 0. */
    @Test
    fun mirrorsServerValuePerAccountAndIsFalseUntilLoaded() = runTest {
        val account = MutableStateFlow<String?>(null)
        val answers = ArrayDeque<Any>(listOf(IllegalStateException("offline"), true, IllegalStateException("offline"), false))
        var calls = 0
        val source = TokenUsageCollectSource(account, fetchCollects = {
            calls++
            when (val a = answers.removeFirst()) {
                is Throwable -> throw a
                else -> a as Boolean
            }
        })
        source.start(backgroundScope)
        runCurrent()
        assertEquals(0, calls, "로그아웃 상태에서 설정을 물었다")
        assertFalse(source.collects)

        account.value = "user-a"
        runCurrent()
        assertEquals(1, calls)
        assertFalse(source.loaded, "실패했는데 받았다고 한다")
        assertFalse(source.collects, "받기 전인데 수집이 참이다")
        advanceTimeBy(TokenUsageCollectSource.RETRY_MILLIS - 1)
        runCurrent()
        assertEquals(1, calls, "재시도 간격 전에 다시 물었다")
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, calls)
        assertTrue(source.loaded)
        assertTrue(source.collects, "서버 값(참)을 옮기지 않았다")

        account.value = "user-b"
        runCurrent()
        assertEquals(3, calls, "계정이 바뀌었는데 새로 묻지 않았다")
        assertFalse(source.loaded, "새 계정 값을 아직 못 받았는데 받았다고 한다")
        assertFalse(source.collects, "새 계정 값을 받기 전에 앞 계정 값(참)이 남았다")
        advanceTimeBy(TokenUsageCollectSource.RETRY_MILLIS)
        runCurrent()
        assertEquals(4, calls)
        assertTrue(source.loaded)
        assertFalse(source.collects, "새 계정의 서버 값(거짓)이 아니다")

        account.value = null
        runCurrent()
        assertFalse(source.loaded, "로그아웃 뒤에도 받은 값이 남았다")
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(4, calls, "로그아웃 상태에서 다시 물었다")
        source.stop()
    }

    /** 계정 전환이 응답보다 빠르면 앞 계정 응답은 버린다(collectLatest 취소) — 다음 계정은 거짓에서 시작. */
    @Test
    fun switchingAccountDropsTheInFlightAnswer() = runTest {
        val account = MutableStateFlow<String?>("user-a")
        val gate = kotlinx.coroutines.CompletableDeferred<Boolean>()
        var second = false
        val source = TokenUsageCollectSource(account, fetchCollects = { if (!second) { second = true; gate.await() } else false })
        source.start(backgroundScope)
        runCurrent()
        account.value = "user-b"
        runCurrent()
        gate.complete(true)
        runCurrent()
        assertTrue(source.loaded)
        assertFalse(source.collects, "앞 계정의 늦은 응답(참)이 새 계정 값을 덮었다")
        source.stop()
    }
}
