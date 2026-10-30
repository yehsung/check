// W2-h3 배경 스캔 주기 — TokenUploadCoordinator.refreshTokenUsageInBackgroundIfDue.
// Swift 원본 WorkTimerStoreSync.swift refreshTokenUsageInBackgroundIfDue 의 ★(롤오버여도 60초 하한)·⚠️(총합 0 근거는 틀렸다)
// = INV-WorkTimerStoreSync-c13b53fa · INV-WorkTimerStoreSync-b6f6f6c2, 시험 V0240TokenScanTests.swift
// rolledOverBackgroundScanKeepsTheSixtySecondFloorAcrossRepeatedTicks · rolloverScansWithRefreshNowWhileSteadyStateGoesThroughTheStaleThrottle.
// 하한이 빠지면 롤오버가 참으로 남는 동안(KST 월 경계 창 · 총합 0 인 달의 다음 실행) 30초 틱마다 전량 순회와 계정 프로브가 돈다.
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class TokenBackgroundScanFloorTest {
    private val now = epoch(1_793_322_123)               // 2026-10-30T01:02:03Z = KST 10:02 → 이번 달 "2026-10"

    /** 스캐너 가짜 — 부른 횟수만 센다. [month] 가 이번 달이 아니면(또는 null) 롤오버. 스캔해도 달은 그대로(롤오버가 계속 참인 창). */
    private class FakeScan(var month: String?) : TokenScanSource {
        var refreshNowCalls = 0
        var refreshIfStaleCalls = 0
        val scans get() = refreshNowCalls + refreshIfStaleCalls
        override val currentMonthUsage: TokenUsageMonthly? get() = month?.let { TokenUsageMonthly(month = it) }
        override val lastScanAt: SwiftDate? = null
        override val lastScanFileCount: Int = 0
        override suspend fun refreshNow() { refreshNowCalls += 1 }
        override suspend fun refreshIfStale() { refreshIfStaleCalls += 1 }
    }

    private class Rig(signedIn: Boolean = true, collect: Boolean = true) {
        val backend = RecordingBackend()
        val host = FakeSessionHost(backend.service).also { if (!signedIn) it.current = null }
        var diagCalls = 0
        // 깃발 기본(꺼짐) — 배경 스캔은 로컬 표시용이라 깃발과 무관하게 돈다(업로드·하트비트만 닫힌다).
        val coordinator = TokenUploadCoordinator(DesktopAppConfig(), host, { "win:dev-1" }, { collect }, InMemoryDesktopKeyValueStore(),
            appBuild = 1, computeDiagnostics = { _, build -> diagCalls += 1; CodexUsageDiagnostics(filesTotal = 0, appBuild = build) })

        suspend fun tick(scan: FakeScan, at: SwiftDate, isWorking: Boolean = true) =
            coordinator.refreshTokenUsageInBackgroundIfDue(scan, null, isWorking, at)
    }

    @Test
    fun star_INV_c13b53fa_rolledOverKeepsTheSixtySecondFloorAcrossRepeatedTicks() = runTest {
        for (month in listOf("2026-09", null)) {          // ⓐ 월 경계 창(지난달 값) · ⓑ 총합 0 인 달의 다음 실행(값 없음)
            val rig = Rig()
            val scan = FakeScan(month)
            for (offset in listOf(0.0, 30.0, 45.0, 59.0)) rig.tick(scan, now.addingTimeInterval(offset))   // 폴링 30초 틱 모양
            assertEquals(1, scan.scans, "★ 롤오버가 참인 동안 매 틱 전량 순회가 돌았다(60초 하한 소실) — month=$month")
            assertEquals(now, rig.coordinator.lastBackgroundTokenScanAt)
            rig.tick(scan, now.addingTimeInterval(60.0))
            assertEquals(2, scan.scans, "롤오버면 주기는 60초(600초가 아니다) — month=$month")
            assertEquals(emptyList(), rig.backend.paths(), "깃발 꺼짐 — 배경 경로로도 업로드·하트비트 0")
            assertEquals(0, rig.diagCalls)
        }
    }

    @Test
    fun steadyStateUsesTheTenMinuteInterval() = runTest {
        val rig = Rig()
        val scan = FakeScan("2026-10")
        for (offset in listOf(0.0, 60.0, 300.0, 599.0)) rig.tick(scan, now.addingTimeInterval(offset))
        assertEquals(1, scan.scans, "평시 주기는 600초")
        rig.tick(scan, now.addingTimeInterval(600.0))
        assertEquals(2, scan.scans)
    }

    @Test
    fun rolloverScansWithRefreshNowWhileSteadyStateGoesThroughTheStaleThrottle() = runTest {
        val rolled = FakeScan("2026-09")
        Rig().tick(rolled, now)
        assertEquals(1 to 0, rolled.refreshNowCalls to rolled.refreshIfStaleCalls, "롤오버는 refreshNow(3초 스로틀 무시 — 2026-09-02 결함)")
        val steady = FakeScan("2026-10")
        Rig().tick(steady, now)
        assertEquals(0 to 1, steady.refreshNowCalls to steady.refreshIfStaleCalls, "평시는 refreshIfStale")
    }

    @Test
    fun backgroundScanNeedsSessionCollectAndWork() = runTest {
        for ((rig, working) in listOf(Rig(signedIn = false) to true, Rig(collect = false) to true, Rig() to false)) {
            val scan = FakeScan(null)
            rig.tick(scan, now, isWorking = working)
            assertEquals(0, scan.scans)
            assertEquals(null, rig.coordinator.lastBackgroundTokenScanAt, "거른 틱은 주기 시각을 찍지 않는다")
        }
    }
}
