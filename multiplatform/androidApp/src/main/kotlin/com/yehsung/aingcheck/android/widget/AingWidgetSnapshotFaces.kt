// 원본: Sources/CheckWidgetsKit/Widgets/AingWidgets.swift @ 3bd04bd (각 위젯의 provider.timeline → 엔트리 값 — 스냅숏을 칸 시각으로 투영해 그릴 값을 고른다)
// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift @ 3bd04bd (AingWidgetMyTodayState · AingWidgetWorking · AingWidgetTodos · AingWidgetLimitsState)
//
// 스냅숏 → 얼굴. 위젯이 그릴 때마다 [read] 로 스냅숏을 한 번 읽고(없으면 로그아웃 — 남의 지난 값을 그리지 않는다) 렌더 순간으로 투영한다.
// 읽기는 조립(K11)이 넘긴다: W2-f FileWidgetSnapshotFile 을 읽어 AingWidgetInput 으로 옮기는 함수 하나(assembly.md).
// 위젯마다 고르는 수가 다르다 — 지금 근무 중 S 얼굴 3 · M 칸 6, 할 일 M 3줄 · L 5줄. 얼굴 하나에 둘을 함께 싣고 그리는 쪽이 크기로 고른다.
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.wire.SwiftDate

class AingWidgetSnapshotFaces(private val read: () -> AingWidgetInput?) : AingWidgetFaceSource {
    private fun now(nowMillis: Long) = SwiftDate(nowMillis / 1000.0)

    override fun workingNow(nowMillis: Long): WorkingNowFace {
        val snapshot = read() ?: return WorkingNowFace.SignedOut()
        val now = now(nowMillis)
        val medium = AingWidgetWorking(snapshot.working, AingWidgetLayout.WORKING_MEDIUM_CELLS)
        val small = AingWidgetWorking(snapshot.working, AingWidgetLayout.WORKING_SMALL_FACES)
        return WorkingNowFace.People(
            total = medium.total,
            shown = medium.shown.map { WorkingPersonFace(it.name, it.teammate, AingWidgetWorking.detail(it, now), it.characterID) },
            namesLine = small.namesLine,
            teammateCount = medium.teammateCount,
            otherCount = medium.otherCount,
            footer = small.smallFooter,
            ago = AingWidgetFormat.ago(snapshot.generatedAt, now),
        )
    }

    override fun myToday(nowMillis: Long): MyTodayFace {
        val snapshot = read() ?: return MyTodayFace.SignedOut
        val now = now(nowMillis)
        val character = snapshot.characterID ?: DEFAULT_CHARACTER
        return when (val state = AingWidgetMyTodayState.of(snapshot, now)) {
            AingWidgetMyTodayState.NoData -> MyTodayFace.Message(AingWidgetText.noData, character)
            AingWidgetMyTodayState.NoTeam -> MyTodayFace.Message(AingWidgetText.noTeam, character)
            is AingWidgetMyTodayState.Me -> {
                val me = state.me
                MyTodayFace.Me(
                    characterId = character,
                    stateTitle = me.stateTitle,
                    tone = me.tone,
                    stateSubtitle = me.stateSubtitle(snapshot.generatedAt, now),
                    timerStartEpochMillis = me.timerStart(now)?.let { (it.timeIntervalSince1970 * 1000).toLong() },
                    // 세는 중이면 렌더 순간의 경과("5:10:00" — iOS Text(timerInterval:) 자리), 멈췄으면 "5시간 10분".
                    todayText = if (me.isTicking) AingWidgetFormat.elapsedLong(me.todaySeconds) else AingWidgetFormat.hoursMinutes(me.todaySeconds),
                    weekCaption = AingWidgetText.weekLine(me.weekCaption),
                    percent = me.percent,
                    progress = me.progress.toFloat(),
                    isGoalComplete = me.isGoalComplete,
                )
            }
        }
    }

    override fun todos(nowMillis: Long): TodosFace {
        val snapshot = read() ?: return TodosFace.SignedOut()
        val now = now(nowMillis)
        val medium = AingWidgetTodos(snapshot.todosPreview, AingWidgetLayout.TODO_ROWS_MEDIUM)
        val large = AingWidgetTodos(snapshot.todosPreview, AingWidgetLayout.TODO_ROWS_LARGE)
        return TodosFace.Rows(
            rows = large.rows.map { TodoRowFace(it.id, it.title, it.isCompleted, AingWidgetTodos.carryBadge(it)) },
            mediumTrailing = medium.mediumTrailing,
            largeSubtitle = large.largeSubtitle(now),
            remaining = large.remaining,
            largeFooter = large.largeFooter(AingWidgetFormat.ago(snapshot.generatedAt, now)),
        )
    }

    override fun aiLimits(nowMillis: Long): AILimitsFace {
        val snapshot = read() ?: return AILimitsFace.SignedOut()
        val now = now(nowMillis)
        return when (val state = AingWidgetLimitsState.of(snapshot, now)) {
            AingWidgetLimitsState.NoData -> AILimitsFace.Message(AingWidgetText.limitsNoData)
            AingWidgetLimitsState.NoProviders -> AILimitsFace.Message(AingWidgetText.limitsNoProviders)
            is AingWidgetLimitsState.Limits -> {
                val limits = state.limits
                val header = limits.headerDevice
                AILimitsFace.Limits(
                    rows = limits.shown(AingWidgetLayout.LIMIT_ROWS_MEDIUM).map { row ->
                        val five = row.display(AILimitWindow.fiveHour)
                        val week = row.display(AILimitWindow.weekly)
                        LimitRowFace(
                            providerName = row.compactName,
                            fiveHourText = AingWidgetLimitFormat.valueText(five),
                            fiveHourPercent = five?.percent,
                            fiveHourFloorOnly = five?.floorOnly ?: false,
                            weeklyText = AingWidgetLimitFormat.valueText(week),
                            weeklyPercent = week?.percent,
                            weeklyFloorOnly = week?.floorOnly ?: false,
                        )
                    },
                    deviceName = header?.name,
                    deviceTail = header?.tail,
                    deviceSpoken = header?.spoken,
                    tokenToday = limits.todayTokens?.let(AingWidgetLimitFormat::tokens),
                    tokenRecent = limits.recentTokens?.let(AingWidgetLimitFormat::tokens),
                    ago = limits.observationAgeText(now),
                )
            }
        }
    }

    companion object {
        /** 착용 캐릭터를 모르면 아잉(위젯 초상의 기본 — 지어내는 것이 아니라 앱의 기본 캐릭터다). */
        const val DEFAULT_CHARACTER = "aing"
    }
}
