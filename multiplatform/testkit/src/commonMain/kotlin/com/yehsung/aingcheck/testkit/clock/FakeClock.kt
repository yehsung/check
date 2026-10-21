// K2 FakeClock — 가상 시간 타이머와 시계가 늘 같은 값을 본다(A§3-3).
package com.yehsung.aingcheck.testkit.clock

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlin.time.Clock
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

/**
 * `TestScope.testScheduler.currentTime`(가상 ms)에서 시각을 만든다. `delay(1.minutes)` 를 지나면 `now()` 도 1분 간다.
 * 기준 시각은 iOS 데모와 같은 **2026-09-17 14:05 KST**(= 05:05Z, R3:65).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FakeClock(
    private val scheduler: TestCoroutineScheduler,
    private val base: Instant = BASE,
) : Clock {
    override fun now(): Instant = base + scheduler.currentTime.milliseconds

    companion object {
        /** 2026-09-17 14:05 KST. */
        val BASE: Instant = Instant.parse("2026-09-17T05:05:00Z")
    }
}

/** 같은 가상 시간에서 나오는 단조 시계(ns). */
@OptIn(ExperimentalCoroutinesApi::class)
class FakeMonotonicClock(private val scheduler: TestCoroutineScheduler) : MonotonicClock {
    override fun elapsedNanos(): Long = scheduler.currentTime * 1_000_000L
}

fun TestScope.fakeClock(base: Instant = FakeClock.BASE): FakeClock = FakeClock(testScheduler, base)

fun TestScope.fakeMonotonicClock(): FakeMonotonicClock = FakeMonotonicClock(testScheduler)
