// 원본: 없음 — W3-b 화면 스냅숏(폰 = Android xhdpi 배율 2 · 360dp × 밝음·어두움). 데모 픽스처로 채운 진짜 스토어를 그린다(①).
//
// 골든: ui/snapshots/screens/{rankings,me,settingscommon}/android/<장면>.png. 진열장 시험(GallerySnapshotAndroidTest)과 같은 세 가지를 잰다:
//  ① 새로 세 번 그려도 같다 ② 골든과 같다(기록 기계 = 픽셀 그대로, 다른 러너 = 굵은 대조) ③ 같은 크기에 한 군데만 다른 장면은 다르다.
// 순위는 **오늘 순위만**(§8-18 #7) — 미니게임 장면에 [오늘|역대] 전환이 없다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h2000dp-xhdpi")
class ScreenSnapshotAndroidTest {
    private val art by lazy { RepoScreenArt(AndroidSnapshots.DENSITY) { AndroidSnapshots.repoImage(it) } }
    private val width = 360
    private val fox = RankingsMyFace("fox", CharacterMood.Working)
    private val foxOff = RankingsMyFace("fox", CharacterMood.Off)
    private val notifications = FixedNotificationSettings(NotificationPermission.Granted, PushPrefs(message = true, gomokuInvite = true, feedbackReply = false), setOf("chess_invite"))

    private fun scene(dark: Boolean, height: Int, content: @Composable (Modifier) -> Unit): @Composable () -> Unit = {
        ScreenScene(dark, art, Modifier.size(width.dp, height.dp), content)
    }

    private fun theme(dark: Boolean) = if (dark) "dark" else "light"

    // ---------------------------------------------------------------- 순위

    private fun league(dark: Boolean) {
        val store = ScreenScenes.rankings(RankingsBoard.league)
        val other = ScreenScenes.rankings(RankingsBoard.league, oneMinuteMore = true)
        check("screens/rankings", "rankings-league-${theme(dark)}", RANKINGS_H, scene(dark, RANKINGS_H) { RankingsScene(store, fox, it) }, scene(dark, RANKINGS_H) { RankingsScene(other, fox, it) })
    }

    @Test fun rankingsLeagueLight() = league(false)
    @Test fun rankingsLeagueDark() = league(true)

    /** AI 토큰 판(내 행 = 착용 캐릭터 초상 · 나 · 비공개 칩). 기준선 = 내 초상 표정만 다르다(근무 중 ↔ 근무 안 함). */
    @Test
    fun rankingsTokensLight() {
        val store = ScreenScenes.rankings(RankingsBoard.tokens)
        check("screens/rankings", "rankings-tokens-light", RANKINGS_H, scene(false, RANKINGS_H) { RankingsScene(store, fox, it) }, scene(false, RANKINGS_H) { RankingsScene(store, foxOff, it) })
    }

    /** 미니게임 판(오늘 순위만 · 어제 1등 · 상품 줄 · 정족수). */
    @Test
    fun rankingsMiniGameDark() {
        val store = ScreenScenes.rankings(RankingsBoard.minigame, MiniGameKind.timingBar)
        check("screens/rankings", "rankings-minigame-dark", RANKINGS_H, scene(true, RANKINGS_H) { RankingsScene(store, fox, it) }, scene(true, RANKINGS_H) { RankingsScene(store, foxOff, it) })
    }

    // ---------------------------------------------------------------- 나

    private fun meHome(dark: Boolean) {
        val store = ScreenScenes.me()
        val other = ScreenScenes.me(rubyOverride = (store.rubyBalance ?: 0) + 1)
        check("screens/me", "me-home-${theme(dark)}", ME_H, scene(dark, ME_H) { MeHomeScene(store, MeStageMood.working, it) }, scene(dark, ME_H) { MeHomeScene(other, MeStageMood.working, it) })
    }

    @Test fun meHomeLight() = meHome(false)
    @Test fun meHomeDark() = meHome(true)

    /** 맥 두 대(묶음 머리글 · 열 머리 한 번) — INV-MeAILimitsCard-f50d3b6f. 기준선 = 둘째 맥 5시간 91 → 41. */
    @Test
    fun aiLimitsTwoDevicesLight() = check(
        "screens/me", "me-ailimits-two-devices-light", AI_H,
        scene(false, AI_H) { AILimitsTableScene("two-devices", it) },
        scene(false, AI_H) { AILimitsTableScene("two-devices-alt", it) },
    )

    /** 상한 길이 이름이 겹친 맥 두 대 — 이름은 잘려도 꼬리 둘이 남는다(INV-MeAILimitsCard-664f60e2 · c6d050c8 좁은 폭). */
    @Test
    fun aiLimitsTwinLongNamesDark() = check(
        "screens/me", "me-ailimits-twin-long-names-dark", AI_H,
        scene(true, AI_H) { AILimitsTableScene("twin-long-names", it) },
        scene(true, AI_H) { AILimitsTableScene("twin-names", it) },
        maxBaselineRatio = 2,
    )

    // ---------------------------------------------------------------- 설정 · 계정 삭제

    private fun settings(dark: Boolean) {
        val store = ScreenScenes.me(settings = true)
        check(
            "screens/settingscommon", "settings-${theme(dark)}", SETTINGS_H,
            scene(dark, SETTINGS_H) { SettingsScene(store, AingAppearanceMode.Dark, notifications, it) },
            scene(dark, SETTINGS_H) { SettingsScene(store, AingAppearanceMode.Light, notifications, it) },
        )
    }

    @Test fun settingsLight() = settings(false)
    @Test fun settingsDark() = settings(true)

    /** 계정 삭제(지워지는 것 · 되돌릴 수 없음 · 비밀번호 · [영구 삭제] 잠김). 기준선 = 비밀번호를 친 뒤([영구 삭제] 가 켜진다). */
    @Test
    fun accountDeletionLight() {
        val store = ScreenScenes.me()
        val typed = ScreenScenes.me().also { it.accountDeletionPassword = "pw" }
        check("screens/settingscommon", "account-deletion-light", DELETION_H, scene(false, DELETION_H) { AccountDeletionScene(store, it) }, scene(false, DELETION_H) { AccountDeletionScene(typed, it) })
    }

    // ---------------------------------------------------------------- 나 탭 하위 화면(잔디 상세 · 캐릭터 고르기 · 프로필 · 제보 · 차단한 사람)

    /** 잔디 상세. 기준선 = 오늘 근무만 2시간 30분 → 2시간(칸 하나 · 막대 글자). */
    @Test
    fun grassDetailLight() {
        val store = ScreenScenes.me(subScreens = true)
        val shorter = ScreenScenes.me(subScreens = true, todayShorter = true)
        check(
            "screens/me", "me-grass-detail-light", GRASS_H,
            scene(false, GRASS_H) { GrassDetailScene(store, com.yehsung.aingcheck.core.stores.me.MeGrassAxis.work, it) },
            scene(false, GRASS_H) { GrassDetailScene(shorter, com.yehsung.aingcheck.core.stores.me.MeGrassAxis.work, it) },
        )
    }

    /** 캐릭터 고르기. 기준선 = 루비 10. */
    @Test
    fun characterPickerDark() {
        val store = ScreenScenes.me(subScreens = true)
        val short = ScreenScenes.me(rubyOverride = 10, subScreens = true)
        check("screens/me", "me-character-picker-dark", PICKER_H, scene(true, PICKER_H) { CharacterPickerScene(store, it) }, scene(true, PICKER_H) { CharacterPickerScene(short, it) })
    }

    /** 프로필. 기준선 = 별명 칸에 "새벽이". */
    @Test
    fun profileLight() {
        val store = ScreenScenes.me(subScreens = true)
        val typed = ScreenScenes.me(subScreens = true).also { it.displayNameDraft = "새벽이" }
        check("screens/me", "me-profile-light", PROFILE_H, scene(false, PROFILE_H) { ProfileScene(store, it) }, scene(false, PROFILE_H) { ProfileScene(typed, it) })
    }

    /** 제보. 그릴 때마다 새 스토어(떠나면 새 답장을 '봤음'으로 적는다). 기준선 = 초안을 쓴 뒤. */
    @Test
    fun feedbackLight() {
        val stores = ArrayDeque(List(3) { ScreenScenes.me(subScreens = true) })
        val typed = ScreenScenes.me(subScreens = true).also { it.feedbackDraft = "위젯이 안 보여요" }
        check(
            "screens/me", "me-feedback-light", FEEDBACK_H,
            scene(false, FEEDBACK_H) { FeedbackScene(androidx.compose.runtime.remember { stores.removeFirst() }, it) },
            scene(false, FEEDBACK_H) { FeedbackScene(typed, it) },
        )
    }

    /** 차단한 사람 두 명. 기준선 = 한 명. */
    @Test
    fun blockedPeopleDark() {
        val two = ScreenScenes.blocked(2)
        val one = ScreenScenes.blocked(1)
        check("screens/settingscommon", "blocked-people-dark", BLOCKED_H, scene(true, BLOCKED_H) { BlockedPeopleScene(two, it) }, scene(true, BLOCKED_H) { BlockedPeopleScene(one, it) })
    }

    /** 알림 설명 시트(다크). 기준선 = 권한 창이 떠 있는 동안. */
    @Test
    fun notificationPrimerDark() = check(
        "screens/settingscommon", "notification-primer-dark", PRIMER_H,
        scene(true, PRIMER_H) { NotificationPrimerScene(PrimerFixture.content(), requesting = false, it) },
        scene(true, PRIMER_H) { NotificationPrimerScene(PrimerFixture.content(), requesting = true, it) },
    )

    @OptIn(ExperimentalTestApi::class)
    private fun render(content: @Composable () -> Unit): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            setContent { Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { content() } }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    private fun check(group: String, name: String, heightDp: Int, scene: @Composable () -> Unit, other: @Composable () -> Unit, maxBaselineRatio: Int = 4) {
        val renders = List(3) { render(scene) }
        val out = AndroidSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                AndroidSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertEquals("$name: 크기", (width * 2) to (heightDp * 2), actual.width to actual.height)
        assertTrue("$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다", actual.distinctColors() >= 64)
        val golden = AndroidSnapshots.golden(group, name)
        if (AndroidSnapshots.recording()) {
            AndroidSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue("$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다", golden.isFile)
        val expected = AndroidSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT android $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            AndroidSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { AndroidSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/android/$name-{actual,diff}.png")
        }
        val baseline = render(other)
        assertEquals("$name: 기준선 크기", actual.width to actual.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android $name diff=$negative coarse=$negativeCoarse")
        assertFalse("$name: 다른 입력인데 같은 픽셀 — 비교가 내용을 못 본다", negative.identical)
        assertTrue("$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다", negative.differingPixels in 1 until actual.argb.size / maxBaselineRatio)
        assertFalse("$name: 굵은 대조가 다른 입력을 못 잡는다($negativeCoarse)", negativeCoarse.withinTolerance)
    }

    private companion object {
        const val TAG = "aingcheck-screen"
        const val RANKINGS_H = 660
        const val ME_H = 1400
        const val SETTINGS_H = 1640
        const val DELETION_H = 580
        const val AI_H = 330
        const val GRASS_H = 860
        const val PICKER_H = 980
        const val PROFILE_H = 940
        const val FEEDBACK_H = 1000
        const val BLOCKED_H = 300
        const val PRIMER_H = 820
    }
}
