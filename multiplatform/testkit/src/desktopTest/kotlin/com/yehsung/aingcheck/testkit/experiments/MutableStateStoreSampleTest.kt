package com.yehsung.aingcheck.testkit.experiments

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.Snapshot
import com.yehsung.aingcheck.testkit.clock.fakeClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Clock

/**
 * C-X7: Swift `@Observable` 스토어를 `mutableStateOf` 로 옮겼을 때, UI(Recomposer) 없는 JVM `runTest` 에서
 * 상태 변화가 **결정적**인가. 견본 스토어는 폴링·재시도·시계 읽기를 섞어 Swift 스토어의 모양을 흉내 낸다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MutableStateStoreSampleTest {
    /** 견본: 시작 → 불러오는 중 → (첫 시도 실패, 2초 뒤 재시도) → 불러옴, 그 뒤 60초마다 폴링. */
    private class SampleStore(private val scope: CoroutineScope, private val clock: Clock) {
        var phase by mutableStateOf("idle")
            private set
        var unread by mutableStateOf(0)
            private set
        var lastLoadedAt by mutableStateOf<String?>(null)
            private set
        private var attempts = 0

        fun start() {
            scope.launch {
                phase = "loading"
                while (true) {
                    attempts += 1
                    delay(300)
                    if (attempts == 1) {
                        phase = "retrying"
                        delay(2_000)
                        continue
                    }
                    unread += attempts
                    lastLoadedAt = clock.now().toString()
                    phase = "loaded"
                    delay(60_000)
                }
            }
        }
    }

    private fun runScenario(): List<String> {
        val trace = mutableListOf<String>()
        val dispatcher = StandardTestDispatcher()
        Dispatchers.setMain(dispatcher)
        try {
            runTest(dispatcher) {
                val clock = fakeClock()
                // 스토어 범위는 runTest 의 자식이 아니다(앱처럼 스토어가 자기 범위를 쥔다). 끝에 거둔다.
                val storeScope = CoroutineScope(Dispatchers.Main + Job())
                val store = SampleStore(storeScope, clock)
                fun snap(label: String) {
                    trace += "$label t=${testScheduler.currentTime} phase=${store.phase} unread=${store.unread} at=${store.lastLoadedAt}"
                }
                snap("init")
                store.start()
                runCurrent(); snap("started")
                testScheduler.advanceTimeBy(301); runCurrent(); snap("after-first")
                testScheduler.advanceTimeBy(2_300); runCurrent(); snap("after-retry")
                testScheduler.advanceTimeBy(60_300); runCurrent(); snap("after-poll")
                storeScope.cancel()
            }
        } finally {
            Dispatchers.resetMain()
        }
        return trace
    }

    @Test
    fun storeStateIsDeterministicWithoutUi() {
        val expected = listOf(
            "init t=0 phase=idle unread=0 at=null",
            "started t=0 phase=loading unread=0 at=null",
            "after-first t=301 phase=retrying unread=0 at=null",
            "after-retry t=2601 phase=loaded unread=2 at=2026-09-17T05:05:02.600Z",
            "after-poll t=62901 phase=loaded unread=5 at=2026-09-17T05:06:02.900Z",
        )
        val runs = (1..20).map { runScenario() }
        println("AINGCHECK-CX7 runs=${runs.size} distinct=${runs.distinct().size}")
        assertEquals(1, runs.distinct().size, "같은 대본인데 상태 흔적이 갈렸다: ${runs.distinct()}")
        assertEquals(expected, runs.first())
    }

    @Test
    fun snapshotFlowObservesStoreWritesWhenApplyNotificationsAreSent() = runTest {
        var value by mutableStateOf(0)
        val seen = mutableListOf<Int>()
        val job = launch { snapshotFlow { value }.collect { seen += it } }
        runCurrent()
        for (next in 1..3) {
            value = next
            // Recomposer 가 없으면 전역 스냅숏 적용 알림을 누군가 보내야 snapshotFlow 가 깨어난다.
            Snapshot.sendApplyNotifications()
            advanceUntilIdle()
        }
        job.cancel()
        assertEquals(listOf(0, 1, 2, 3), seen)
    }
}
