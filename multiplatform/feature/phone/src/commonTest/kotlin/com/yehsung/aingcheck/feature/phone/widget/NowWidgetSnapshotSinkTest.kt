// 원본: Tests/CheckMobileKitTests/NowWidgetSnapshotTests.swift(카드 · 사람 · 할 일 · 소속 없음 · 리밋 칸 · 로그아웃) ·
//       Sources/CheckMobileKit/Now/NowStore.swift:694-823 · NowStoreAILimits.swift @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.work.PhoneWorkServer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class NowWidgetSnapshotSinkTest {
    private fun TestScope.rig(noTeam: Boolean = false): PhoneHarness {
        val server = PhoneWorkServer()
        val h = PhoneHarness(this) { r ->
            if (noTeam && r.path == "/rest/v1/memberships") Reply.Json("[]") else server.route(r)
        }
        h.signIn()
        return h
    }

    private fun snapshot(h: PhoneHarness): WidgetSnapshot = assertNotNull(WidgetSnapshotCodec.decode(assertNotNull(h.widgetFile.bytes, "스냅숏 파일이 있어야 한다")))

    private val panel = MeAILimitWidgetPanel(
        providers = listOf(MeAILimitWidgetRow("claude", 30.0, null, null, null, SwiftDate(1_789_621_000.0))),
        todayTokens = 12,
    )

    @Test
    fun refreshWritesMyCardWorkingPeopleAndTodos() = runTest {
        val h = rig()
        h.app.now.refresh()
        advanceUntilIdle()
        val s = snapshot(h)
        val me = assertNotNull(s.me)
        assertTrue(me.working)
        assertEquals(WidgetSnapshot.WorkState.working, me.status)
        assertEquals(SwiftISO8601.parse("2026-09-17T01:20:00Z"), me.sessionStartedAt, "위젯이 스스로 세도록 서버 세션 시작 시각")
        assertEquals(40, me.goalHours)
        assertEquals(emptyList(), s.working, "나는 '지금 근무 중' 목록에 없다")
        assertTrue(s.generatedAt <= h.now() && s.generatedAt >= SwiftDate(1_789_621_500.0), "generatedAt 은 쓴 순간의 세션 시계")
        assertTrue(h.widgetReloads >= 1)
    }

    @Test
    fun noTeamWritesSentinelAndAILimitsLiveBesideItNotInsideIt() = runTest {
        val h = rig(noTeam = true)
        h.app.now.refresh()
        advanceUntilIdle()
        assertEquals(NowWidgetSnapshotSink.noTeamMe, snapshot(h).me, "소속 없음 = 목표 0시간인 me(센티넬)")
        // INV-WidgetSnapshot-5dc1a78a: 리밋은 최상위 칸이다 — 리밋을 실어도 소속 없음 센티넬 비교가 흔들리지 않는다.
        h.app.widgetSink.noteAILimitPanel(panel)
        val withLimits = snapshot(h)
        assertEquals(panel, withLimits.aiLimits)
        assertEquals(NowWidgetSnapshotSink.noTeamMe, withLimits.me, "리밋을 실은 뒤에도 소속 없음 판정 그대로")
        // 지금 탭이 다시 써도 리밋 칸을 지우지 않는다(쓰기 창구가 현재 값을 읽어 고친다 — 칸마다 자기 몫만).
        h.app.now.refresh()
        advanceUntilIdle()
        assertEquals(panel, snapshot(h).aiLimits)
    }

    @Test
    fun signedOutWritesNothingAndSignOutClearsTheFile() = runTest {
        val h = rig()
        h.app.now.refresh()
        advanceUntilIdle()
        assertNotNull(h.widgetFile.bytes)
        h.app.session.signOut()
        advanceUntilIdle()
        assertNull(h.widgetFile.bytes, "로그아웃은 스냅숏을 지운다(세션의 onLocalUserDataCleared 고리)")
        assertNull(h.app.widgets.current)
        h.app.widgetSink.noteAILimitPanel(panel)
        h.app.widgetSink.write(deferWhileRefreshing = false)
        assertNull(h.widgetFile.bytes, "로그아웃 뒤 다시 쓰면 위젯이 앞 계정을 그린다 — 쓰지 않는다")
    }

    @Test
    fun knownEquippedCharacterOverwritesButUnknownKeepsThePreviousValue() = runTest {
        // 나 탭이 착용값을 알면(로그인 직후 primeEquippedCharacter — 서버값 null = 기본 아잉) 그 값을 싣는다.
        val known = rig()
        known.app.now.refresh()
        advanceUntilIdle()
        assertTrue(known.app.me.equippedLoaded)
        assertEquals("aing", snapshot(known).characterID)
        // 착용값을 못 받았으면(오프라인) 칸을 건드리지 않는다 — 지난 실행이 쓴 값을 지킨다.
        val seeded = WidgetSnapshot(generatedAt = SwiftDate(1_789_621_000.0), characterID = "fox")
        val server = PhoneWorkServer()
        val unknown = PhoneHarness(this, widgetFile = com.yehsung.aingcheck.feature.phone.MemoryWidgetFile(WidgetSnapshotCodec.encode(seeded))) { r ->
            if (r.path == "/rest/v1/profiles") Reply.Offline else server.route(r)
        }
        unknown.signIn()
        unknown.app.now.refresh()
        advanceUntilIdle()
        assertTrue(!unknown.app.me.equippedLoaded)
        assertEquals("fox", snapshot(unknown).characterID, "모르는 동안 지난 값을 지운다면 위젯 초상이 아잉으로 깜빡인다")
        assertNotNull(snapshot(unknown).me, "다른 칸은 새로 썼다")
    }
}
