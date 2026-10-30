// 원본: multiplatform/desktopApp/src/test/…/pages/shared/SharedPagesSnapshotDesktopTest.kt(오프스크린 ImageComposeScene · 골든 대조 틀)
// W3-c2 홈 스냅숏 — 근무 전 · 근무 중 · 대기 · 12시간 확인 · 배너 셋(업데이트 · 공지 · 오목 신청) × 배율 100·150 × 밝음·어두움.
// 골든: desktopApp/src/test/kotlin/…/pages/work/golden/home-<장면>-<배율>-<밝기>.png. 기록은 맥 arm64 에서만(AINGCHECK_SNAPSHOT_RECORD=1 —
// 기록 실행은 실패로 끝난다). 다른 러너는 굵은 대조. 픽스처는 합성(실제 사람·팀 없음). 박자 없음(tickMillis = null) — 무한 루프 0.
package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

class HomePageSnapshotTest {
    private enum class Scale(val percent: Int, val density: Float) { S100(100, 1f), S150(150, 1.5f) }

    private val failures = mutableListOf<String>()
    private val recorded = mutableListOf<String>()

    private fun golden(name: String): File =
        File(DesktopSnapshots.mpRoot, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/pages/work/golden/$name.png")

    private fun outFile(name: String): File = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/pages-work/$name.png")

    private val team: List<TeamMemberStatus> = listOf(
        HomeTestKit.member(HomeTestKit.ME, "나", working = false, weekly = 18L * 3600 + 20 * 60),
        HomeTestKit.member("u-2", "하늘", working = true, startedAgo = 47 * 60, weekly = 31L * 3600),
        HomeTestKit.member("u-3", "가람", working = true, startedAgo = 3 * 3600, weekly = 12L * 3600, lastSeenAgo = 8 * 60),
        HomeTestKit.member("u-4", "팀원10", working = false, weekly = 41L * 3600),
        HomeTestKit.member("u-5", "팀원2", working = false, weekly = 2L * 3600),
    )

    private class Scene(
        val snapshot: DesktopWorkSnapshot,
        val meWorking: Boolean = false,
        val update: DesktopUpdateState? = null,
        val gomoku: DuelInviteBanner? = null,
    )

    private fun teamFor(s: Scene): List<TeamMemberStatus> = if (!s.meWorking) team else team.map {
        if (it.id == HomeTestKit.ME) it.copy(status = com.yehsung.aingcheck.core.wire.models.WorkStatus.working, currentSessionStartedAt = HomeTestKit.ago(65 * 60)) else it
    }

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(scene: Scene, dark: Boolean, scale: Scale): PixelImage {
        val w = HomeTestKit.FakeWork(scene.snapshot)
        val deps = HomePageDeps(
            work = w,
            commands = w,
            teamStatuses = MutableStateFlow(teamFor(scene)),
            clock = { HomeTestKit.NOW },
            isSignedIn = { true },
            isTeamless = { false },
            myUserId = { HomeTestKit.ME },
            teamName = { "합성 팀" },
            teamGoalSeconds = { 40L * 3600 },
            duelsEnabled = true,
            update = scene.update?.let { MutableStateFlow(it) },
            inviteCode = { "AB12CD" },
            bannerFeed = { HomeBannerFeed(gomoku = scene.gomoku) },
            tickMillis = null,
        )
        val page = HomePage(deps)
        val width = (WIDTH_DIP * scale.density).toInt()
        val height = (HEIGHT_DIP * scale.density).toInt()
        val ics = ImageComposeScene(width = width, height = height, density = Density(scale.density)) {
            AingTheme(dark = dark) { page.Content(InMemoryFlyoutNavigator(), WIDTH_DIP.toDouble()) }
        }
        try {
            var image: Image? = null
            for (i in 0 until FRAMES) {
                image?.close()
                image = ics.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(width * height)
            for (y in 0 until height) for (x in 0 until width) pixels[y * width + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(width, height, pixels)
        } finally {
            ics.close()
        }
    }

    private fun check(name: String, actual: PixelImage) {
        assertTrue(actual.distinctColors() > 2, "$name: 장면이 비었다(색 ${actual.distinctColors()})")
        DesktopSnapshots.writePng(actual, outFile(name))
        val file = golden(name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, file)
            recorded += name
            return
        }
        if (!file.isFile) {
            failures += "$name: 골든 없음($file)"
            return
        }
        val expected = DesktopSnapshots.readPng(file)
        if (SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))) {
            val d = SnapshotCompare.diff(expected, actual)
            if (!d.identical) failures += "$name: $d"
        } else {
            val c = SnapshotCompare.coarse(expected, actual)
            if (!c.withinTolerance) failures += "$name: $c"
        }
    }

    @Test
    fun homeScenes() {
        val working = DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(65 * 60), accumulatedTodaySeconds = 2 * 3600, accumulatedDayStart = HomeTestKit.ago(5 * 3600))
        val scenes = linkedMapOf(
            "before" to Scene(DesktopWorkSnapshot()),
            "working" to Scene(working, meWorking = true),
            "pending" to Scene(working.copy(pendingSync = true), meWorking = true),
            "twelve-hour" to Scene(working.copy(longSessionPromptShownAt = HomeTestKit.ago(60)), meWorking = true),
            "banner-update" to Scene(DesktopWorkSnapshot(), update = DesktopUpdateState(currentBuild = 70, latestBuild = 72, latestVersion = "0.3.68")),
            "banner-notice" to Scene(
                DesktopWorkSnapshot(),
                update = DesktopUpdateState(currentBuild = 72, notice = AppNotice(id = "n-1", title = "합성 공지 제목", body = "공지 본문 한 줄 — 합성 픽스처", linkLabel = "자세히 보기")),
            ),
            "banner-duel" to Scene(working, meWorking = true, gomoku = DuelInviteBanner("m-1", "합성상대", 5, HomeTestKit.NOW.addingTimeInterval(45.0))),
        )
        for ((key, scene) in scenes) for (dark in listOf(false, true)) for (scale in Scale.entries) {
            check("home-$key-${scale.percent}-${if (dark) "dark" else "light"}", render(scene, dark, scale))
        }
        if (recorded.isNotEmpty()) fail("기록 실행(${recorded.size}장) — 골든을 다시 썼다. 기록 실행은 초록으로 끝나지 않는다: $recorded")
        if (failures.isNotEmpty()) fail("스냅숏 ${failures.size}건: $failures")
    }

    private companion object {
        const val WIDTH_DIP = 414
        const val HEIGHT_DIP = 640
        const val FRAMES = 4
    }
}
