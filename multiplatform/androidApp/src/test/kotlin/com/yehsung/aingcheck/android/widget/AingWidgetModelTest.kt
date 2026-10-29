// 원본: Tests/CheckMobileKitTests/NowWidgetTests.swift @ 3bd04bd (내 오늘 투영 · 경계 · 상태 · 고르기 · 서식)
// 원본: Tests/CheckMobileKitTests/WidgetAILimitsTests.swift @ 3bd04bd (리밋 투영 · 코어 규칙 값 · 0% · 고르기 · 칸 · 빈 상태 · 토큰 · 유령 · 머리 나이)
// 원본: Tests/CheckMobileKitTests/MeAILimitDeviceTests.swift:293 @ 3bd04bd (합친 이름 + 꼬리 → 두 조각)
//
// Swift 시험과 **같은 입력 · 같은 기대값**(데모 시각 2026-09-17 14:05 KST 목). 위젯 값 계산(AingWidgetModel.kt)과 스냅숏 → 얼굴(AingWidgetSnapshotFaces)을 잰다.
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.AILimitGhostRow
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AingWidgetModelTest {
    private val now: SwiftDate = SessionClock.demoInstant
    private fun at(offset: Double) = now.addingTimeInterval(offset)
    private fun me(working: Boolean, started: SwiftDate?, today: Int, week: Int, goal: Int = 40, status: AingWidgetInput.WorkState? = null) =
        AingWidgetInput.Me(working, started, today, week, goal, status)

    // ---------------------------------------------------------------- 내 오늘 투영

    @Test
    fun meProjectionTicks() {
        val atTen = at(600.0)
        val projected = AingWidgetMe(me(true, at(-13_500.0), 18_600, 89_280), now, atTen)
        assertTrue(projected.isWorking && projected.isTicking)
        assertEquals(19_200, projected.todaySeconds)
        assertEquals(89_880, projected.weekSeconds)
        assertEquals(atTen.addingTimeInterval(-19_200.0), projected.timerStart(atTen))
        assertEquals(62, projected.percent)
        assertEquals("24.9/40시간", projected.weekCaption)

        val still = AingWidgetMe(me(false, null, 4_020, 146_000), now, atTen)
        assertTrue(!still.isTicking && still.todaySeconds == 4_020 && still.timerStart(atTen) == null)
        assertTrue(still.isGoalComplete && still.progress == 1.0)
        assertEquals(101, still.percent)

        // 연결이 끊긴 세션(앱이 시작 시각을 싣지 않음)은 근무 중이어도 세지 않는다.
        val frozen = AingWidgetMe(me(true, null, 100, 200), now, atTen)
        assertTrue(frozen.isWorking && !frozen.isTicking && frozen.todaySeconds == 100)
    }

    @Test
    fun meProjectionBoundaries() {
        val midnight = TeamWeeklyGoal.koreanDayStart(now).addingTimeInterval(86_400.0) // 9/18 00:00 KST
        val generatedAt = midnight.addingTimeInterval(-600.0)
        val working = me(true, midnight.addingTimeInterval(-7_200.0), 30_000, 100_000)
        val afterMidnight = AingWidgetMe(working, generatedAt, midnight.addingTimeInterval(300.0))
        assertEquals("어제 누적이 오늘로 넘어왔다", 300, afterMidnight.todaySeconds)
        assertEquals("같은 주는 이어 센다", 100_900, afterMidnight.weekSeconds)

        val idle = me(false, null, 30_000, 100_000)
        assertEquals(0, AingWidgetMe(idle, generatedAt, midnight.addingTimeInterval(300.0)).todaySeconds)

        val monday = TeamWeeklyGoal.koreanWeekStart(now).addingTimeInterval(7 * 86_400.0)
        val beforeMonday = monday.addingTimeInterval(-60.0)
        val newWeek = AingWidgetMe(me(true, monday.addingTimeInterval(-3_600.0), 3_540, 150_000), beforeMonday, monday.addingTimeInterval(120.0))
        assertEquals(120, newWeek.weekSeconds)
        assertEquals(120, newWeek.todaySeconds)
        assertEquals(0, AingWidgetMe(idle, beforeMonday, monday.addingTimeInterval(120.0)).weekSeconds)

        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        val old = AingWidgetMe(me(true, at(-1_000.0), 1_000, 1_000), dayStart.addingTimeInterval(60.0), dayStart.addingTimeInterval(60.0 + 13 * 3_600))
        assertFalse("12시간 넘은 스냅숏을 계속 셌다", old.isTicking)
        assertEquals("12시간 지점에서 멈춘다", 1_000 + 12 * 3_600, old.todaySeconds)
    }

    @Test
    fun myTodayState() {
        val empty = AingWidgetInput(generatedAt = now)
        assertEquals(AingWidgetMyTodayState.NoData, AingWidgetMyTodayState.of(empty, now))
        assertEquals(AingWidgetMyTodayState.NoTeam, AingWidgetMyTodayState.of(empty.copy(me = me(false, null, 0, 0, goal = 0)), now))
        val member = AingWidgetMyTodayState.of(empty.copy(me = me(false, null, 0, 0, goal = 1)), now)
        assertTrue("목표 1시간인 팀원을 소속 없음으로 그렸다", member is AingWidgetMyTodayState.Me)
        member as AingWidgetMyTodayState.Me
        assertEquals(1, member.me.goalHours)
        assertEquals(0, member.me.percent)
        assertNotEquals(AingWidgetText.noTeam, AingWidgetText.noData)
        assertFalse("Android 판은 '맥 앱에서'라고 하지 않는다(폰 가입이 있다 — E§7.1)", AingWidgetText.noTeam.contains("맥"))
    }

    @Test
    fun stateTitleToneAndSubtitle() {
        val working = AingWidgetMe(me(true, at(-60.0), 60, 60, status = AingWidgetInput.WorkState.working), now, now)
        assertEquals("근무 중" to WidgetTone.Working, working.stateTitle to working.tone)
        val lost = AingWidgetMe(me(true, null, 60, 60, status = AingWidgetInput.WorkState.disconnected), now, now)
        assertEquals("연결 끊김" to WidgetTone.Lost, lost.stateTitle to lost.tone)
        val off = AingWidgetMe(me(false, null, 60, 60, status = AingWidgetInput.WorkState.working), now, now)
        assertEquals("깃발이 꺼져 있으면 상태 칸과 무관하게 근무 안 함", "근무 안 함" to WidgetTone.Off, off.stateTitle to off.tone)
        // 멈춘 값이 한 시간 넘게 낡았으면 "N시간 전 기준", 세는 값·덜 낡은 값은 "오늘 누적".
        val generated = at(-7_300.0)
        assertEquals("2시간 전 기준", AingWidgetMe(me(false, null, 60, 60), generated, now).stateSubtitle(generated, now))
        assertEquals("오늘 누적", AingWidgetMe(me(false, null, 60, 60), at(-1_800.0), now).stateSubtitle(at(-1_800.0), now))
        assertEquals("오늘 누적", AingWidgetMe(me(true, at(-8_000.0), 60, 60), generated, now).stateSubtitle(generated, now))
    }

    // ---------------------------------------------------------------- 고르기 · 서식

    @Test
    fun selections() {
        val working = listOf(
            AingWidgetInput.Person("코랄", null, false, null),
            AingWidgetInput.Person("민트", "seoul", true, now),
            AingWidgetInput.Person("하늘", null, false, null),
            AingWidgetInput.Person("라임", null, true, now),
        )
        val small = AingWidgetWorking(working, limit = 3)
        assertEquals(listOf("민트", "라임", "코랄"), small.shown.map { it.name })
        assertEquals(4, small.total)
        assertEquals(1, small.hiddenCount)
        assertEquals("우리 팀 2 · 외 1명", small.smallFooter)
        assertEquals("민트 · 라임 · 코랄", small.namesLine)
        assertEquals(0, AingWidgetWorking(emptyList(), limit = 6).total)
        assertNull("둘 다 없으면 아래 줄이 없다", AingWidgetWorking(listOf(AingWidgetInput.Person("코랄", null, false, null)), 3).smallFooter)
        assertEquals(listOf(listOf("민트", "라임", "코랄"), listOf("하늘")), AingWidgetWorking(working, 6).columns(3).map { col -> col.map { it.name } })
        assertEquals("우리 팀은 경과", "4:10", AingWidgetWorking.detail(AingWidgetInput.Person("민트", "seoul", true, at(-15_000.0)), now))
        assertEquals("다른 팀은 센터", "부산", AingWidgetWorking.detail(AingWidgetInput.Person("코랄", "busan", false, null), now))
        assertNull(AingWidgetWorking.detail(AingWidgetInput.Person("하늘", null, false, null), now))

        val todos = (0 until 5).map { AingWidgetInput.Todo("id$it", "t$it", it == 1, it) }
        val medium = AingWidgetTodos(todos, limit = 3)
        assertEquals(listOf("id0", "id1", "id2"), medium.rows.map { it.id })
        assertEquals(2, medium.hiddenCount)
        assertEquals(4, medium.remaining)
        assertEquals("남은 4개 · 외 2개", medium.mediumTrailing)
        assertEquals("9월 17일 목 · 5개 중 1개 완료", medium.largeSubtitle(now))
        assertEquals("외 2개 · 2분 전", medium.largeFooter("2분 전"))
        assertEquals("2분 전", AingWidgetTodos(todos, 5).largeFooter("2분 전"))
        assertNull(AingWidgetTodos.carryBadge(todos[0]))
        assertEquals("어제", AingWidgetTodos.carryBadge(todos[1]))
        assertEquals("3일 전", AingWidgetTodos.carryBadge(todos[3]))
    }

    @Test
    fun formats() {
        assertEquals("방금", AingWidgetFormat.ago(now, at(59.0)))
        assertEquals("미래(시계 차)는 방금", "방금", AingWidgetFormat.ago(now, at(-30.0)))
        assertEquals("2분 전", AingWidgetFormat.ago(now, at(125.0)))
        assertEquals("2시간 전", AingWidgetFormat.ago(now, at(7_300.0)))
        assertEquals("2일 전", AingWidgetFormat.ago(now, at(200_000.0)))
        assertEquals("3시간 25분", AingWidgetFormat.hoursMinutes(12_300))
        assertEquals("0분", AingWidgetFormat.hoursMinutes(59))
        assertEquals("24.8", AingWidgetFormat.hoursOneDecimal(89_280))
        assertEquals("반을 0 에서 멀리(62.5 → 63)", 63, AingWidgetFormat.percent(90_000, 144_000))
        assertEquals(999, AingWidgetFormat.percent(Int.MAX_VALUE / 2, 3600))
        assertEquals("0:00", AingWidgetFormat.elapsedClock(at(60.0), now))
        assertEquals("5:10:00", AingWidgetFormat.elapsedLong(18_600))
        // 머리 나이 글자의 경계는 코어 나이 문구와 같다(화면마다 '방금'이 갈리지 않게).
        for (age in listOf(0.0, 59.0, 60.0, 61.0, 3_599.0, 3_600.0, 86_399.0, 86_400.0, 200_000.0)) {
            assertEquals("${age}초", FeedbackText.ageText(at(-age), now), AingWidgetFormat.ago(at(-age), now))
        }
    }

    // ---------------------------------------------------------------- AI 리밋

    private fun row(provider: String, five: Double? = null, fiveReset: Double? = null, week: Double? = null, weekReset: Double? = null, observed: Double = -30.0) =
        MeAILimitWidgetRow(provider, five, fiveReset?.let(::at), week, weekReset?.let(::at), at(observed))

    private fun panel(rows: List<MeAILimitWidgetRow>, today: Long? = null, recent: Long? = null, name: String? = null, tail: String? = null) =
        MeAILimitWidgetPanel(rows, name, tail, today, recent)

    private val basePanel = panel(
        listOf(row("claude", 27.0, 9_000.0, 60.0, 450_000.0), row("codex", 56.0, 1_800.0, 31.0, 200_000.0)),
        today = 12_345_678, recent = 19_658_964_272,
    )

    private fun snapshot(p: MeAILimitWidgetPanel?) = AingWidgetInput(
        generatedAt = at(-30.0),
        me = me(true, at(-3_600.0), 3_600, 7_200, status = AingWidgetInput.WorkState.working),
        aiLimits = p,
    )

    private fun limits(p: MeAILimitWidgetPanel, date: SwiftDate = now): AingWidgetLimits {
        val state = AingWidgetLimitsState.of(snapshot(p), date)
        assertTrue("리밋 상태가 아니다: $state", state is AingWidgetLimitsState.Limits)
        return (state as AingWidgetLimitsState.Limits).limits
    }

    @Test
    fun projectsAbsoluteResetToRemaining() {
        fun resetText(offset: Double): String? {
            val date = at(offset)
            val claude = limits(basePanel, date).rows.first { it.provider == AILimitProvider.claude }
            return AingWidgetLimitFormat.resetIn(claude.fiveHour?.resetsAt?.let { SwiftDate(it) }, date)
        }
        assertEquals("2시간 뒤 초기화", resetText(0.0))
        assertEquals("1시간 뒤 초기화", resetText(5_400.0))
        assertEquals("5분 뒤 초기화", resetText(8_700.0))
        assertNull("리셋이 지났는데 '뒤 초기화'를 말한다", resetText(9_100.0))
        assertEquals("1분", AingWidgetLimitFormat.remainingText(1.0))
        assertEquals("1분", AingWidgetLimitFormat.remainingText(59.0))
        assertEquals("59분", AingWidgetLimitFormat.remainingText(3_599.0))
        assertEquals("1시간", AingWidgetLimitFormat.remainingText(3_600.0))
        assertEquals("23시간", AingWidgetLimitFormat.remainingText(86_399.0))
        assertEquals("2일", AingWidgetLimitFormat.remainingText(200_000.0))
        assertNull(AingWidgetLimitFormat.resetIn(null, now))
    }

    @Test
    fun valuesComeFromCoreRule() {
        val l = limits(panel(listOf(row("claude", 72.0, 3_600.0, observed = -3_600.0), row("codex", 94.0, -600.0, observed = -1_200.0))))
        val claude = l.rows.first { it.provider == AILimitProvider.claude }.fiveHour!!
        assertEquals("72% 이상", claude.valueText)
        assertTrue(claude.floorOnly)
        val codex = l.rows.first { it.provider == AILimitProvider.codex }.fiveHour!!
        assertEquals("0%", codex.valueText)
        assertEquals("초기화됨", codex.captionText)
        assertEquals(0.0, codex.percent!!, 0.0)
    }

    @Test
    fun zeroPercentDoesNotClaimReset() {
        val five = limits(panel(listOf(row("codex", 0.0, null, 56.0, 200_000.0, observed = -300.0)))).rows.first().fiveHour!!
        assertEquals("0%", five.valueText)
        assertFalse("0% 를 '초기화됨'으로 단정했다", five.freshness.isResetClaim)
        assertEquals("5분 전", five.captionText)
        assertNull(AingWidgetLimitFormat.resetIn(five.resetsAt?.let { SwiftDate(it) }, now))
    }

    @Test
    fun dropsUnknownAndEmptyAndKeepsFixedOrder() {
        val l = limits(panel(listOf(
            row("antigravity", week = 8.0, weekReset = 500_000.0, observed = 0.0),
            row("future-provider", 99.0, observed = 0.0),
            row("claude", 27.0, observed = 0.0),
            row("codex", observed = 0.0),
        )))
        assertEquals("모르는 제공자·빈 행이 살아남거나 순서가 흔들렸다", listOf(AILimitProvider.claude, AILimitProvider.antigravity), l.rows.map { it.provider })
        assertEquals(2, l.shown(AingWidgetLayout.LIMIT_ROWS_MEDIUM).size)
        assertEquals(listOf(AILimitProvider.claude), l.shown(1).map { it.provider })
    }

    @Test
    fun everyWindowGetsItsOwnCell() {
        val l = limits(panel(listOf(
            row("claude", 27.0, 9_000.0, 60.0, 450_000.0, observed = 0.0),
            row("antigravity", week = 8.0, weekReset = 500_000.0, observed = 0.0),
        )))
        val claude = l.rows.first { it.provider == AILimitProvider.claude }
        assertEquals("27%", claude.display(AILimitWindow.fiveHour)?.valueText)
        assertEquals("60%", claude.display(AILimitWindow.weekly)?.valueText)
        val ag = l.rows.first { it.provider == AILimitProvider.antigravity }
        assertNull("없는 5시간 창을 지어냈다", ag.display(AILimitWindow.fiveHour))
        assertEquals("없음", AingWidgetLimitFormat.valueText(ag.display(AILimitWindow.fiveHour)))
        assertEquals("8%", ag.display(AILimitWindow.weekly)?.valueText)
        assertFalse(AingWidgetLimitRow(AILimitProvider.codex, null, null, null).hasAnyWindow)
        assertEquals(AILimitWindow.fiveHour.displayName, AingWidgetText.limitsFiveHour)
        assertEquals(AILimitWindow.weekly.displayName, AingWidgetText.limitsWeekly)
    }

    @Test
    fun twoEmptyStatesAreDistinct() {
        assertEquals(AingWidgetLimitsState.NoData, AingWidgetLimitsState.of(snapshot(null), now))
        assertEquals(AingWidgetLimitsState.NoProviders, AingWidgetLimitsState.of(snapshot(panel(emptyList())), now))
        assertEquals(AingWidgetLimitsState.NoProviders, AingWidgetLimitsState.of(snapshot(panel(listOf(row("future-provider", 50.0, observed = 0.0)))), now))
        assertNotEquals(AingWidgetText.limitsNoData, AingWidgetText.limitsNoProviders)
    }

    @Test
    fun tokenAxisIsSeparate() {
        val with = limits(basePanel)
        val without = limits(panel(basePanel.providers))
        assertTrue(with.hasTokens && with.todayTokens == 12_345_678L)
        assertTrue("모르는 토큰을 0 으로 지어냈다", !without.hasTokens && without.todayTokens == null)
        assertEquals(TokenNumberFormatter.compactKorean(12_345_678), AingWidgetLimitFormat.tokens(12_345_678))
        assertEquals("196.6억", AingWidgetLimitFormat.tokens(19_658_964_272))
    }

    @Test
    fun widgetHidesGhostRowsAtEntryTime() {
        val cutoff = AILimitGhostRow.maxObservationAge
        assertTrue(cutoff > 86_400)
        fun ghostPanel(age: Double) = panel(listOf(row("claude", 27.0, -age + 600, observed = -age)))
        fun shown(p: MeAILimitWidgetPanel, date: SwiftDate = now): List<AILimitProvider> =
            (AingWidgetLimitsState.of(snapshot(p), date) as? AingWidgetLimitsState.Limits)?.limits?.rows?.map { it.provider } ?: emptyList()
        assertEquals(listOf(AILimitProvider.claude), shown(ghostPanel(cutoff - 1)))
        assertEquals(emptyList<AILimitProvider>(), shown(ghostPanel(cutoff)))
        val written = ghostPanel(2.5 * 86_400)
        assertEquals(listOf(AILimitProvider.claude), shown(written))
        assertEquals("칸 시각으로 다시 재지 않아 유령 줄을 그린다", AingWidgetLimitsState.NoProviders, AingWidgetLimitsState.of(snapshot(written), at(86_400.0)))
        val mixed = panel(listOf(row("claude", 27.0, 9_000.0, observed = -300.0), row("codex", 56.0, observed = -cutoff - 60)))
        assertEquals(listOf(AILimitProvider.claude), shown(mixed))
        assertEquals("미래 관측은 여기서 버리지 않는다(코어가 unknown 으로 판정)", listOf(AILimitProvider.claude), shown(ghostPanel(-7_200.0)))
    }

    @Test
    fun headerAgeSpeaksOfTheObservationNotTheFileWrite() {
        val p = panel(listOf(row("claude", 27.0, 3_600.0, observed = -10_800.0), row("codex", 56.0, 1_800.0, observed = -600.0)))
        val l = (AingWidgetLimitsState.of(snapshot(p).copy(generatedAt = now), now) as AingWidgetLimitsState.Limits).limits
        assertEquals("3시간 전", l.observationAgeText(now))
        assertEquals(at(-10_800.0), l.oldestObservedAt)
        assertEquals("4시간 전", l.observationAgeText(at(3_600.0)))
        assertNull(AingWidgetLimits.of(panel(emptyList()), now).observationAgeText(now))
    }

    @Test
    fun deviceNamePartsSplitOnlyWhenTheyRoundTrip() {
        val maxName = "거실에 둔 맥 미니 " + "길".repeat(54)
        assertEquals(AILimitDeviceNameParts(maxName, "A1B2"), AingWidgetLimits.deviceNameParts("$maxName (A1B2)", "A1B2"))
        assertEquals("꼬리가 없으면 그대로", AILimitDeviceNameParts("Mac mini", null), AingWidgetLimits.deviceNameParts("Mac mini", null))
        assertEquals("짝이 안 맞으면(옛 파일) 꼬리 없이", AILimitDeviceNameParts("Mac mini (ZZZZ)", null), AingWidgetLimits.deviceNameParts("Mac mini (ZZZZ)", "A1B2"))
        assertEquals("이름이 비면 가르지 않는다", AILimitDeviceNameParts(" (A1B2)", null), AingWidgetLimits.deviceNameParts(" (A1B2)", "A1B2"))
        val header = limits(panel(basePanel.providers, name = "Mac mini (A1B2)", tail = "A1B2")).headerDevice!!
        assertEquals(AingWidgetLimitsHeaderDevice("· Mac mini", "(A1B2)", "Mac mini (A1B2)"), header)
        assertNull("맥이 한 대면 머리에 적지 않는다", limits(basePanel).headerDevice)
        assertNull("공백뿐인 이름은 없는 것", limits(panel(basePanel.providers, name = "   ")).headerDevice)
    }

    /** 머리 한 줄: 긴 이름은 그 안에서 말줄임하고 겹침 꼬리는 늘 남는다(RemoteViews 에 layoutPriority 가 없어 글자 단계에서 지킨다). */
    @Test
    fun headerLineKeepsTheTwinTail() {
        assertNull(LimitsHeaderLine.deviceText(null, "A1B2"))
        assertEquals("· Mac mini (A1B2)", LimitsHeaderLine.deviceText("· Mac mini", "(A1B2)"))
        assertEquals("· Mac mini", LimitsHeaderLine.deviceText("· Mac mini", null))
        val longName = "· 거실에 둔 맥 미니 " + "길".repeat(40)
        val twinA = LimitsHeaderLine.deviceText(longName, "(A1B2)")!!
        val twinB = LimitsHeaderLine.deviceText(longName, "(C3D4)")!!
        assertTrue(twinA, twinA.endsWith("… (A1B2)"))
        assertNotEquals("두 쌍둥이 머리가 글자 그대로 같다", twinA, twinB)
        assertEquals(LimitsHeaderLine.MAX_NAME + " (A1B2)".length, twinA.codePointCount(0, twinA.length))
    }

    // ---------------------------------------------------------------- 스냅숏 → 얼굴

    private val sample = AingWidgetInput(
        generatedAt = at(-120.0),
        me = me(true, at(-13_620.0), 18_480, 89_280, status = AingWidgetInput.WorkState.working),
        working = listOf(
            AingWidgetInput.Person("민트", "seoul", true, at(-15_000.0), "shiba"),
            AingWidgetInput.Person("보리", "busan", true, at(-10_320.0), "aing"),
            AingWidgetInput.Person("라임", "seoul", true, at(-5_700.0), "jellyfish"),
            AingWidgetInput.Person("모래", "seoul", false, null, "ghost"),
            AingWidgetInput.Person("코랄", "busan", false, null, "squirrel"),
            AingWidgetInput.Person("하늘", null, false, null),
            AingWidgetInput.Person("바다", null, false, null),
        ),
        todosPreview = listOf(
            AingWidgetInput.Todo("a", "디자인 리뷰 피드백 반영하기", false, 0),
            AingWidgetInput.Todo("b", "주간 회고 초안 쓰기", false, 1),
            AingWidgetInput.Todo("c", "팀 회의 안건 정리", false, 3),
            AingWidgetInput.Todo("d", "점심 전에 PR 올리기", true, 0),
            AingWidgetInput.Todo("e", "온보딩 문서 링크 모으기", false, 9),
            AingWidgetInput.Todo("f", "여섯째", false, 0),
        ),
        characterID = "fox",
        aiLimits = basePanel.copy(deviceName = "Mac mini (A1B2)", deviceNameTail = "A1B2"),
    )

    private val nowMillis = (now.timeIntervalSince1970 * 1000).toLong()

    @Test
    fun snapshotFacesProjectAtRenderTime() {
        val faces = AingWidgetSnapshotFaces { sample }
        val working = faces.workingNow(nowMillis) as WorkingNowFace.People
        assertEquals(7, working.total)
        assertEquals("M 은 여섯 칸까지", 6, working.shown.size)
        assertEquals("민트 · 보리 · 라임", working.namesLine)
        assertEquals("S 아래 줄은 S 한도(3)로 센다", "우리 팀 3 · 외 4명", working.footer)
        assertEquals("4:10", working.shown.first().detail)
        assertEquals("2분 전", working.ago)

        val today = faces.myToday(nowMillis) as MyTodayFace.Me
        assertEquals("fox", today.characterId)
        assertEquals("근무 중", today.stateTitle)
        assertEquals("세는 중이면 렌더 순간의 경과", "5:10:00", today.todayText)
        assertEquals("이번 주 24.8/40시간", today.weekCaption)
        assertEquals((now.timeIntervalSince1970 * 1000).toLong() - 18_600_000L, today.timerStartEpochMillis)

        val todos = faces.todos(nowMillis) as TodosFace.Rows
        assertEquals("L 은 다섯 줄", listOf("a", "b", "c", "d", "e"), todos.rows.map { it.id })
        assertEquals("M 머리는 M 한도(3)로 센다", "남은 5개 · 외 3개", todos.mediumTrailing)
        assertEquals("외 1개 · 2분 전", todos.largeFooter)
        assertEquals(listOf(null, "어제", "3일 전", null, "9일 전"), todos.rows.map { it.carryBadge })

        val limits = faces.aiLimits(nowMillis) as AILimitsFace.Limits
        assertEquals(listOf("Claude", "Codex"), limits.rows.map { it.providerName })
        assertEquals("27%", limits.rows[0].fiveHourText)
        assertEquals("· Mac mini", limits.deviceName)
        assertEquals("(A1B2)", limits.deviceTail)
        assertEquals("Mac mini (A1B2)", limits.deviceSpoken)
        assertEquals(TokenNumberFormatter.compactKorean(12_345_678), limits.tokenToday)
        assertEquals("방금", limits.ago)
    }

    @Test
    fun snapshotFacesFallBackToMessagesAndSignedOut() {
        val bare = AingWidgetSnapshotFaces { AingWidgetInput(generatedAt = now) }
        assertEquals(MyTodayFace.Message(AingWidgetText.noData, "aing"), bare.myToday(nowMillis))
        assertEquals(AILimitsFace.Message(AingWidgetText.limitsNoData), bare.aiLimits(nowMillis))
        val noTeam = AingWidgetSnapshotFaces { AingWidgetInput(generatedAt = now, me = me(false, null, 0, 0, goal = 0), characterID = "ghost") }
        assertEquals(MyTodayFace.Message(AingWidgetText.noTeam, "ghost"), noTeam.myToday(nowMillis))
        val stopped = AingWidgetSnapshotFaces { AingWidgetInput(generatedAt = now, me = me(false, null, 12_300, 0)) }
        assertEquals("멈춘 값은 시간·분", "3시간 25분", (stopped.myToday(nowMillis) as MyTodayFace.Me).todayText)
        // 로그아웃(스냅숏 없음): 네 위젯 모두 로그인 안내 — 남의 지난 값을 그리지 않는다.
        val signedOut = AingWidgetSnapshotFaces { null }
        assertTrue(signedOut.workingNow(nowMillis) is WorkingNowFace.SignedOut)
        assertEquals(MyTodayFace.SignedOut, signedOut.myToday(nowMillis))
        assertTrue(signedOut.todos(nowMillis) is TodosFace.SignedOut)
        assertTrue(signedOut.aiLimits(nowMillis) is AILimitsFace.SignedOut)
    }
}
