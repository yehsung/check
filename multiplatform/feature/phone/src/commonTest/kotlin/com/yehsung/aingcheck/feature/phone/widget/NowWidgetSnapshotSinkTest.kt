// 원본: Tests/CheckMobileKitTests/NowWidgetTests.swift(카드 · 사람 · 할 일 · 소속 없음) · BaseWidgetSnapshotTests.swift:119-152(착용 캐릭터) ·
//       WidgetAILimitsTests.swift(리밋 칸) ·
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
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class NowWidgetSnapshotSinkTest {
    private fun TestScope.rig(noTeam: Boolean = false): PhoneHarness {
        val server = PhoneWorkServer()
        val h = PhoneHarness(this) { r ->
            when {
                noTeam && r.path == "/rest/v1/memberships" -> Reply.Json("[]")
                // 할 일 동기화는 함수가 없는 서버로(조용히 접힌다 — 경로 없는 418 은 재시도가 가상 시간을 끝없이 민다).
                r.rpcName == "todo_sync" -> Reply.missingFunction
                else -> server.route(r)
            }
        }
        h.signIn()
        return h
    }

    /**
     * 할 일 파일이 열린 뒤에는 가상 시간을 끝까지 밀지 않는다 — 할 일 동기화의 5분 주기 타이머(TodoSyncRules.periodicSeconds)가 스스로 다시 걸려
     * advanceUntilIdle 이 끝나지 않는다(요청 기록이 쌓여 OOM). 디바운스(1.5초)·쓰기가 끝날 만큼만 민다.
     */
    private fun TestScope.settleAfterTodoOpened() {
        advanceTimeBy(10_000)
        runCurrent()
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

    /**
     * 사람 · 할 일 칸(W2-f 검증 7차 지적: 앞 시험은 이름과 달리 근무 중 사람을 빈 목록만 보고 할 일을 재지 않았다). 팀원은 경과 시작 시각과 얼굴
     * 캐릭터를 싣고, 다른 팀 사람은 근무 여부만(경과 시각 없음 — 남의 근무 길이를 위젯에 퍼뜨리지 않는다). 할 일은 지금 계정 파일의 줄.
     */
    @Test
    fun peopleCarryTeammateStartAndFaceAndTodosArePreviewed() = runTest {
        val teammate = "00000000-0000-4000-8000-0000000000aa"
        val stranger = "00000000-0000-4000-8000-0000000000bb"
        val h = PhoneHarness(this, drawableCharacters = listOf("aing", "fox", "ghost")) { r ->
            when {
                r.rpcName == "app_user_characters" -> Reply.Json("""[{"user_id":"$teammate","character":"fox"},{"user_id":"$stranger","character":"ghost"}]""")
                r.rpcName == "app_user_directory" -> Reply.Json(
                    """[{"user_id":"$teammate","display_name":"팀원","is_working":true},{"user_id":"$stranger","display_name":"남","is_working":true}]""",
                )
                r.path == "/rest/v1/work_statuses" -> Reply.Json(
                    """[{"user_id":"${PhoneHarness.ME}","status":"working","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","active_session_id":"S-OPEN","profiles":{"display_name":"나","avatar_url":null}},""" +
                        """{"user_id":"$teammate","status":"working","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","active_session_id":"S-TEAM","profiles":{"display_name":"팀원","avatar_url":null}}]""",
                )
                r.path == "/rest/v1/work_sessions" && r.query.any { it.second == "is.null" } -> Reply.Json(
                    """[{"id":"S-OPEN","user_id":"${PhoneHarness.ME}","started_at":"2026-09-17T01:20:00Z","ended_at":null},""" +
                        """{"id":"S-TEAM","user_id":"$teammate","started_at":"2026-09-17T02:00:00Z","ended_at":null}]""",
                )
                r.rpcName == "todo_sync" -> Reply.missingFunction
                else -> PhoneWorkServer().route(r)
            }
        }
        h.signIn()
        h.app.now.appDidBecomeActive()
        settleAfterTodoOpened()
        assertTrue(h.app.now.addTodo("우유 사기"), "전제: 지금 계정 파일이 열렸다")
        h.app.now.refresh()
        settleAfterTodoOpened()
        val s = snapshot(h)
        val team = s.working.single { it.teammate }
        assertEquals("팀원", team.name)
        assertEquals(SwiftISO8601.parse("2026-09-17T02:00:00Z"), team.startedAt, "팀원은 위젯이 스스로 세도록 근무 시작 시각")
        assertEquals("fox", team.characterID, "근무 중 얼굴은 캐릭터 한 표의 착용값")
        val other = s.working.single { !it.teammate }
        assertEquals("남", other.name)
        assertNull(other.startedAt, "다른 팀 사람의 근무 길이를 싣지 않는다")
        assertEquals("ghost", other.characterID)
        assertEquals(listOf("우유 사기"), s.todosPreview.map { it.title }, "할 일 미리보기")
        assertEquals(false, s.todosPreview.single().isCompleted)
    }

    /** 위젯 할 일 체크(W3-b 패처의 구현): 그 줄 체크 표시만 · generatedAt 그대로 · 로그아웃이면 아무것도 안 한다. 기준선: 모르는 id 는 쓰지 않는다. */
    @Test
    fun widgetTodoCheckPatchesOnlyThatRowAndKeepsGeneratedAt() = runTest {
        val h = rig()
        h.app.now.appDidBecomeActive()
        settleAfterTodoOpened()
        assertTrue(h.app.now.addTodo("우유 사기"))
        settleAfterTodoOpened()
        val before = snapshot(h)
        val row = before.todosPreview.single()
        val writes = h.widgetFile.writes
        assertFalse(h.app.widgetSink.patchTodo("ffffffff-0000-4000-8000-000000000000", true), "모르는 id 는 아무것도 바꾸지 않는다")
        assertEquals(writes, h.widgetFile.writes)
        h.clockShift += 120.0
        assertTrue(h.app.widgetSink.patchTodo(row.id.uppercase(), true))
        val after = snapshot(h)
        assertEquals(true, after.todosPreview.single().isCompleted, "그 줄의 체크 표시")
        assertEquals(before.generatedAt, after.generatedAt, "generatedAt 을 옮기면 근무 중 누적에서 그 사이 시간이 빠진다")
        assertEquals(before.me, after.me)
        assertEquals(writes + 1, h.widgetFile.writes)
        h.app.session.signOut()
        settleAfterTodoOpened()
        assertFalse(h.app.widgetSink.patchTodo(row.id, false), "로그아웃 뒤에는 지운 파일을 다시 만들지 않는다")
        assertNull(h.widgetFile.bytes)
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
