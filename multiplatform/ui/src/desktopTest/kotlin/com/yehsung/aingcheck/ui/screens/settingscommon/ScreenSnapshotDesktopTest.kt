// 원본: 없음 — W3-b 화면 스냅숏(데스크톱 오프스크린 배율 2 · 밝음·어두움). 데모 픽스처로 채운 진짜 스토어를 그린다.
//
// 골든: ui/snapshots/screens/{rankings,me,settingscommon}/desktop/<장면>.png. 장면마다 진열장 시험(GallerySnapshotDesktopTest)과 같은 세 가지를 잰다:
//  ① 새로 세 번 그려도 같다 ② 골든과 같다(기록 기계 = 픽셀 그대로, 다른 러너 = 굵은 대조) ③ 같은 크기에 한 군데만 다른 장면은 다르다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class ScreenSnapshotDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }
    private val width = 380
    private val meFace = RankingsMyFace("fox", CharacterMood.Working)
    private val notifications = FixedNotificationSettings(NotificationPermission.Granted, PushPrefs(message = true, gomokuInvite = true, feedbackReply = false), setOf("chess_invite"))

    private fun scene(dark: Boolean, height: Int, content: @Composable (Modifier) -> Unit): @Composable () -> Unit = {
        ScreenScene(dark, art, Modifier.size(width.dp, height.dp), content)
    }

    private val league by lazy { ScreenScenes.rankings(RankingsBoard.league) }
    private val pastLeague by lazy { ScreenScenes.rankings(RankingsBoard.league, oneMinuteMore = true) }
    private val me by lazy { ScreenScenes.me() }
    private val meOther by lazy { ScreenScenes.me(rubyOverride = (me.rubyBalance ?: 0) + 1) }
    private val settingsStore by lazy { ScreenScenes.me(settings = true) }

    private fun rankingsLeague(dark: Boolean) = check(
        "screens/rankings", "rankings-league-${theme(dark)}", RANKINGS_H,
        scene(dark, RANKINGS_H) { RankingsScene(league, meFace, it) },
        scene(dark, RANKINGS_H) { RankingsScene(pastLeague, meFace, it) },
    )

    private fun meHome(dark: Boolean) = check(
        "screens/me", "me-home-${theme(dark)}", ME_H,
        scene(dark, ME_H) { MeHomeScene(me, MeStageMood.working, it) },
        scene(dark, ME_H) { MeHomeScene(meOther, MeStageMood.working, it) },
    )

    private fun settings(dark: Boolean) = check(
        "screens/settingscommon", "settings-${theme(dark)}", SETTINGS_H,
        scene(dark, SETTINGS_H) { SettingsScene(settingsStore, AingAppearanceMode.Dark, notifications, it) },
        scene(dark, SETTINGS_H) { SettingsScene(settingsStore, AingAppearanceMode.Light, notifications, it) },
    )

    // ---------------------------------------------------------------- 나 탭 하위 화면(잔디 상세 · 캐릭터 고르기 · 프로필 · 제보 · 차단한 사람)

    private val sub by lazy { ScreenScenes.me(subScreens = true) }
    private val subShort by lazy { ScreenScenes.me(rubyOverride = 10, subScreens = true) }
    private val subTyped by lazy { ScreenScenes.me(subScreens = true).also { it.displayNameDraft = "새벽이"; it.feedbackDraft = "위젯이 안 보여요" } }

    /** 떠날 때 상태를 바꾸는 화면(제보 — 떠나면 새 답장을 '봤음'으로 적는다)은 그릴 때마다 새 스토어를 쓴다(세 번 그려 같은지 재는 자리). */
    private fun fresh(make: () -> com.yehsung.aingcheck.core.stores.me.MeStore): () -> com.yehsung.aingcheck.core.stores.me.MeStore {
        val stores = ArrayDeque(List(3) { make() })
        return { stores.removeFirst() }
    }

    /** 잔디 상세(오늘에 링 · 아래 막대에 오늘 값). 기준선 = 오늘 근무만 2시간 30분 → 2시간(칸 하나 · 막대 글자). */
    @Test
    fun grassDetailLight() {
        val shorter = ScreenScenes.me(subScreens = true, todayShorter = true)
        check(
            "screens/me", "me-grass-detail-light", GRASS_H,
            scene(false, GRASS_H) { GrassDetailScene(sub, com.yehsung.aingcheck.core.stores.me.MeGrassAxis.work, it) },
            scene(false, GRASS_H) { GrassDetailScene(shorter, com.yehsung.aingcheck.core.stores.me.MeGrassAxis.work, it) },
        )
    }

    /** 캐릭터 고르기(착용 중 여우 · 가진 것 먼저 · 가격 · 뽑기 · 선물). 기준선 = 루비 10(가격 줄이 '모자라요'로 흐려진다). */
    @Test
    fun characterPickerLight() = check(
        "screens/me", "me-character-picker-light", PICKER_H,
        scene(false, PICKER_H) { CharacterPickerScene(sub, it) },
        scene(false, PICKER_H) { CharacterPickerScene(subShort, it) },
    )

    /** 프로필(착용 캐릭터 얼굴 · 별명 · 상태메시지 · 착용 캐릭터 줄). 기준선 = 별명 칸에 "새벽이"(글자 수 · [저장]이 켜진다). */
    @Test
    fun profileLight() = check(
        "screens/me", "me-profile-light", PROFILE_H,
        scene(false, PROFILE_H) { ProfileScene(sub, it) },
        scene(false, PROFILE_H) { ProfileScene(subTyped, it) },
    )

    /** 제보(쓰기 카드 · 내가 보낸 제보 세 줄 · 답장). 기준선 = 초안을 쓴 뒤(글자 수 · [보내기]가 켜진다). */
    @Test
    fun feedbackLight() {
        val next = fresh { ScreenScenes.me(subScreens = true) }
        check(
            "screens/me", "me-feedback-light", FEEDBACK_H,
            scene(false, FEEDBACK_H) { FeedbackScene(androidx.compose.runtime.remember { next() }, it) },
            scene(false, FEEDBACK_H) { FeedbackScene(subTyped, it) },
        )
    }

    /** 차단한 사람 두 명. 기준선 = 한 명(줄 하나가 빠진다). */
    @Test
    fun blockedPeopleLight() {
        val two = ScreenScenes.blocked(2)
        val one = ScreenScenes.blocked(1)
        check(
            "screens/settingscommon", "blocked-people-light", BLOCKED_H,
            scene(false, BLOCKED_H) { BlockedPeopleScene(two, it) },
            scene(false, BLOCKED_H) { BlockedPeopleScene(one, it) },
        )
    }

    /** 알림 설명 시트(종 든 아잉 · 종류 다섯 · 아래 막대). 기준선 = 권한 창이 떠 있는 동안(두 단추가 잠긴다). */
    @Test
    fun notificationPrimerLight() = check(
        "screens/settingscommon", "notification-primer-light", PRIMER_H,
        scene(false, PRIMER_H) { NotificationPrimerScene(PrimerFixture.content(), requesting = false, it) },
        scene(false, PRIMER_H) { NotificationPrimerScene(PrimerFixture.content(), requesting = true, it) },
    )

    @Test fun rankingsLeagueLight() = rankingsLeague(false)
    @Test fun rankingsLeagueDark() = rankingsLeague(true)
    @Test fun meHomeLight() = meHome(false)
    @Test fun meHomeDark() = meHome(true)
    @Test fun settingsLight() = settings(false)
    @Test fun settingsDark() = settings(true)

    private fun theme(dark: Boolean) = if (dark) "dark" else "light"

    private fun check(group: String, name: String, heightDp: Int, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val renders = List(3) { DesktopSnapshots.render(width, heightDp, content = scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = DesktopSnapshots.golden(group, name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue(golden.isFile, "$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            DesktopSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/desktop/$name-{actual,diff}.png")
        }
        val baseline = DesktopSnapshots.render(width, heightDp, content = other)
        assertEquals(actual.width to actual.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 다른 입력인데 같은 픽셀 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until actual.argb.size / 4, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 다른 입력을 못 잡는다($negativeCoarse)")
    }

    companion object {
        const val RANKINGS_H = 660
        const val ME_H = 1400
        const val SETTINGS_H = 1640
        const val GRASS_H = 860
        const val PICKER_H = 980
        const val PROFILE_H = 940
        const val FEEDBACK_H = 1000
        const val BLOCKED_H = 300
        const val PRIMER_H = 820
    }
}
