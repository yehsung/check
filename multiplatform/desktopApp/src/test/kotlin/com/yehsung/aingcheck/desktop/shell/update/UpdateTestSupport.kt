// W3-c5 시험 기반 — 합성 픽스처만(실제 서버·계정 0). 가짜 조회기는 부른 시각(가상 시계 ms)을 적는다.
@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.testkit.mock.MockRouter
import io.ktor.client.HttpClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.TestCoroutineScheduler

internal class FakeUpdateRpc(
    var release: () -> WindowsClientRelease = { WindowsClientRelease(status = "ok") },
    var notice: () -> AppNotice? = { null },
) : UpdateRpc {
    var now: () -> Long = { 0L }
    val releaseCalls = mutableListOf<Long>()
    val noticeCalls = mutableListOf<Long>()
    var gate: CompletableDeferred<Unit>? = null

    override suspend fun clientRelease(): WindowsClientRelease {
        releaseCalls += now()
        gate?.await()
        return release()
    }

    override suspend fun currentNotice(): AppNotice? {
        noticeCalls += now()
        return notice()
    }
}

internal fun virtualMonotonic(scheduler: TestCoroutineScheduler): MonotonicClock = object : MonotonicClock {
    override fun elapsedNanos(): Long = scheduler.currentTime * 1_000_000L
}

internal object PlainTextRules : WireTextRules {
    override fun sanitized(raw: String): String = raw.trim()
    override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
    override fun statusMessageSanitized(raw: String): String = raw.trim()
}

internal const val STUB_ANON: String = "stub-anon-key"

internal fun stubService(router: MockRouter, anonKey: String? = STUB_ANON): SupabaseWorkService = SupabaseWorkService(
    projectURL = "https://golden.invalid",
    anonKey = anonKey,
    client = HttpClient(router.engine) { SupabaseWorkService.clientConfig(this) },
    clock = { SwiftDate.fromEpochMillis(0) },
    text = PlainTextRules,
    newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
)

internal fun notice(id: String, title: String = "공지 $id", body: String = "본문 $id"): AppNotice = AppNotice(id = id, title = title, body = body)
