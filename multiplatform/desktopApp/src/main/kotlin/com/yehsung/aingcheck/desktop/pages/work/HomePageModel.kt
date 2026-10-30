// 원본: Sources/check/CheckMenuView.swift:1579-1629(HeaderCard — 상태 글자 · 오늘 타이머 · WorkTogglePill · 대기 색) · 1633-1643(TodayTimerText)
//       · 1672-1700(HeaderGoalSection — "이번 주 H시간 MM분 / N시간" · 퍼센트) · CheckComponents.swift:7-46(WorkTogglePill — 문구 · enabled=canSync)
//       · WorkTimerStore.swift:1868-1876(myLiveWeeklySeconds — 내 행 라이브 주간, 없으면 오늘 누적) · 1880-1882(canSync = hasAnonKey)
//       · 2019-2025(toggle — 스토어 상태로 시작/종료를 고른다) · 2074(start 가드 startedAt == nil) · 2138-2139(stop 가드)
// W3-c2 — 홈 페이지 순수 모델(시계는 주입). 화면은 [HomePage] 가 이것만 그린다.
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.core.stores.now.NowFormat
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.desktop.pages.banners.BannerCandidates
import com.yehsung.aingcheck.desktop.pages.banners.BannerQueue
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.pages.team.TeamPanelModel
import com.yehsung.aingcheck.desktop.pages.team.TeamPanelUi
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot

/** 상태 글자 색(맥 statusTint 1623-1628): 대기 > 근무 > 종료. */
enum class HeaderTint { PENDING, WORKING, OFF_WORK }

/** 근무 알약(WorkTogglePill). */
data class WorkPillUi(val isWorking: Boolean, val label: String, val enabled: Boolean)

data class HeaderUi(
    val statusText: String,
    val tint: HeaderTint,
    val todayText: String,
    val pill: WorkPillUi,
    val weeklyText: String,
    val percentText: String,
    val goalProgress: Double,
    val goalComplete: Boolean,
)

data class HomeUi(
    val header: HeaderUi,
    val team: TeamPanelUi,
    val banner: TopBanner?,
    val duelInvite: DuelInviteBanner?,
)

/** 모델 입력 — 한 장면의 사실 전부(시각 [now] 는 밖에서 준다). */
data class HomeInputs(
    val snapshot: DesktopWorkSnapshot,
    val members: List<TeamMemberStatus>,
    val myUserId: String?,
    val teamName: String,
    val teamGoalSeconds: Long,
    val syncMessage: String?,
    val inviteCode: String?,
    val canSync: Boolean,
    /** 12시간 후보는 [snapshot] 에서 채운다 — 여기 값은 무시된다. */
    val banners: BannerCandidates,
)

object HomePageModel {
    /** WorkTogglePill 문구(CheckComponents.swift:20). */
    fun pillLabel(isWorking: Boolean): String = if (isWorking) "근무 종료" else "근무 시작"

    fun tint(s: DesktopWorkSnapshot): HeaderTint = when {
        s.pendingSync -> HeaderTint.PENDING
        s.isWorking -> HeaderTint.WORKING
        else -> HeaderTint.OFF_WORK
    }

    /** 맥 `store.snapshot.localizedStatus` — core/rules [WorkStatusSnapshot] 그대로("동기화 대기" · "근무중" · "근무종료"). */
    fun statusText(s: DesktopWorkSnapshot, now: SwiftDate): String =
        WorkStatusSnapshot(if (s.isWorking) WorkStatus.working else WorkStatus.offWork, s.elapsedSeconds(now), s.pendingSync).localizedStatus

    /** 맥 myLiveWeeklySeconds: 내 행이 있으면 그 행의 라이브 주간, 없으면 오늘 누적. */
    fun myLiveWeeklySeconds(inputs: HomeInputs, now: SwiftDate): Long {
        val uid = inputs.myUserId ?: return inputs.snapshot.todaySeconds(now)
        val mine = inputs.members.firstOrNull { it.id == uid } ?: return inputs.snapshot.todaySeconds(now)
        return mine.liveWeeklyDurationSeconds(now)
    }

    fun header(inputs: HomeInputs, now: SwiftDate): HeaderUi {
        val s = inputs.snapshot
        val worked = myLiveWeeklySeconds(inputs, now)
        val goal = TeamWeeklyGoal(worked, inputs.teamGoalSeconds)
        return HeaderUi(
            statusText = statusText(s, now),
            tint = tint(s),
            todayText = MenuBarStatusFormatter.duration(s.todaySeconds(now)),
            pill = WorkPillUi(isWorking = s.isWorking, label = pillLabel(s.isWorking), enabled = inputs.canSync),
            weeklyText = "이번 주 ${MenuBarStatusFormatter.hoursMinutes(worked)} / ${inputs.teamGoalSeconds / 3600}시간",
            percentText = "${NowFormat.percent(worked.toInt(), inputs.teamGoalSeconds.toInt())}%",
            goalProgress = goal.progress,
            goalComplete = goal.isComplete,
        )
    }

    fun candidates(inputs: HomeInputs): BannerCandidates =
        inputs.banners.copy(longSessionPrompt = TwelveHourConfirm.isActive(inputs.snapshot))

    fun build(inputs: HomeInputs, now: SwiftDate): HomeUi {
        val c = candidates(inputs)
        val banner = BannerQueue.pick(c)
        return HomeUi(
            header = header(inputs, now),
            team = TeamPanelModel.build(
                teamName = inputs.teamName,
                members = inputs.members,
                now = now,
                teamGoalSeconds = inputs.teamGoalSeconds,
                myUserId = inputs.myUserId,
                syncMessage = inputs.syncMessage,
                inviteCode = inputs.inviteCode,
            ),
            banner = banner,
            duelInvite = BannerQueue.duelInvite(banner, c),
        )
    }

    /**
     * 알약 한 번 눌림 = [DesktopWorkCommands.toggle] 한 번(맥 `store.toggle()`). 시작/종료는 **스토어 지금 상태**가 고른다 —
     * 화면이 그린(낡을 수 있는) 상태로 고르지 않는다. 그래서 빠른 두 번 눌림 = 시작 → 종료(맥과 같다, SwiftUI Button 은 막지 않는다),
     * 동기화 대기 중 눌림도 막지 않는다(맥 알약 enabled 는 canSync 만 — 대기는 색·글자만 바꾼다). [enabled] 거짓이면 0.
     * @return 명령을 냈는가.
     */
    fun pressWorkToggle(enabled: Boolean, commands: DesktopWorkCommands): Boolean {
        if (!enabled) return false
        commands.toggle()
        return true
    }
}
