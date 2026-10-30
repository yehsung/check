// W3-c2 시험 공용 — 합성 픽스처만(실제 사람·팀 없음). 시계는 고정 시각(2026-10-28 수 14:00 KST).
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.desktop.pages.banners.BannerCandidates
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

internal object HomeTestKit {
    /** 2026-10-28T05:00:00Z = 14:00 KST(수). */
    val NOW: SwiftDate = SwiftDate(java.time.Instant.parse("2026-10-28T05:00:00Z").epochSecond.toDouble())
    fun ago(seconds: Long): SwiftDate = NOW.addingTimeInterval(-seconds.toDouble())

    const val ME = "u-me"

    fun member(
        id: String,
        name: String,
        working: Boolean,
        startedAgo: Long? = null,
        weekly: Long = 0,
        lastSeenAgo: Long? = null,
    ) = TeamMemberStatus(
        id = id,
        name = name,
        status = if (working) WorkStatus.working else WorkStatus.offWork,
        updatedAt = lastSeenAgo?.let(::ago) ?: NOW,
        currentSessionStartedAt = startedAgo?.let(::ago),
        weeklyDurationSeconds = weekly,
        lastSeenAt = lastSeenAgo?.let(::ago),
    )

    /** 근무 스토어처럼 상태를 바꾸는 가짜 명령(맥 start 가드 startedAt == nil · stop 가드 startedAt != nil 과 같은 꼴). */
    class FakeWork(initial: DesktopWorkSnapshot = DesktopWorkSnapshot()) : DesktopWorkState, DesktopWorkCommands {
        val flow = MutableStateFlow(initial)
        override val snapshot: StateFlow<DesktopWorkSnapshot> get() = flow
        val log = mutableListOf<String>()
        override fun toggle() {
            log += "toggle"
            if (flow.value.isWorking) doStop() else doStart()
        }
        override fun start(origin: WorkStartOrigin) {
            log += "start:$origin"
            doStart()
        }
        override fun stop() {
            log += "stop"
            doStop()
        }
        override fun confirmStillWorking() {
            log += "confirm"
            flow.value = flow.value.copy(longSessionPromptShownAt = null)
        }
        override fun resumeRecentlyClosed() {
            log += "resume"
        }
        val transitions = mutableListOf<String>()
        private fun doStart() {
            if (flow.value.startedAt != null) return
            transitions += "started"
            flow.value = flow.value.copy(isWorking = true, startedAt = NOW, startOrigin = WorkStartOrigin.MANUAL)
        }
        private fun doStop() {
            if (flow.value.startedAt == null) return
            transitions += "stopped"
            flow.value = flow.value.copy(isWorking = false, startedAt = null, startOrigin = null, longSessionPromptShownAt = null)
        }
    }

    fun inputs(
        snapshot: DesktopWorkSnapshot = DesktopWorkSnapshot(),
        members: List<TeamMemberStatus> = emptyList(),
        canSync: Boolean = true,
        banners: BannerCandidates = BannerCandidates(isSignedIn = true, isTeamless = false),
    ) = HomeInputs(
        snapshot = snapshot,
        members = members,
        myUserId = ME,
        teamName = "합성 팀",
        teamGoalSeconds = 40L * 3600,
        syncMessage = "동기화됨",
        inviteCode = null,
        canSync = canSync,
        banners = banners,
    )

    /** 저장소 뿌리(multiplatform 의 부모) — 맥 Swift 원본 대조용. */
    val repoRoot: File get() = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 없음" }).parentFile

    fun swiftSource(rel: String): String = File(repoRoot, rel).readText()

    /** 줄 주석(`//` 뒤)을 걷는다 — 주석 속 낱말이 계약 대조를 속이지 않게(기억: 소스 계약 시험은 주석 걷기). 문자열 안 `//` 는 이 파일들에 없다. */
    fun stripLineComments(src: String): String = src.lines().joinToString("\n") { line ->
        val i = line.indexOf("//")
        if (i >= 0) line.substring(0, i) else line
    }
}
