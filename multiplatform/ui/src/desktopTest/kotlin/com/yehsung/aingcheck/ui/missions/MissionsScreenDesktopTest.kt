// 원본: Tests/CheckMobileKitTests/V1013MissionPageTests.swift @ 3bd04bd (미션 화면 세 묶음 · 순서) · Tests/CheckMobileKitTests/MeDailyMissionViewTests.swift @ 3bd04bd (일일 줄 그림)
//
// 「미션」 화면(데스크톱 오프스크린) — 진짜 나 탭 스토어를 데모 픽스처(미션 · 일일 · 이번 주 근무)로 채워 그린다.
//  ① 스냅숏(밝음 · 어두움) · 받기 연출 한 순간
//  ② 순서: 일일 → 이번 주 근무 → 누적(맥 0.3.64 와 같은 순서)
//  ③ 일일 줄은 **서버가 주는 대로**(G §8-18 7): 서버가 일곱 번째 줄(길건너)을 주면 일곱 줄이 선다(기준선: 여섯 줄 응답은 여섯 줄)
//  ④ 서버에 기능이 없으면 그 절이 통째로 빠진다(INV-MeMissionsView-ea2bbdd7): 일일 없는 응답 → 일일 카드 0
package com.yehsung.aingcheck.ui.missions

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.shop.MeScene
import com.yehsung.aingcheck.ui.shop.MeScreenFixtures
import com.yehsung.aingcheck.ui.shop.W4cDesktopSnapshots
import com.yehsung.aingcheck.ui.shop.loadedMeStore
import com.yehsung.aingcheck.ui.shop.replacingOnce
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class MissionsScreenDesktopTest {
    private fun store(workedSeconds: Int = 83520, achievements: String = MeScreenFixtures.achievements): MeStore =
        loadedMeStore(
            MeScene(
                weekly = MeScreenFixtures.weekly.replacingOnce("\"worked_seconds\": 83520", "\"worked_seconds\": $workedSeconds"),
                achievements = achievements,
            ),
        )

    /** [gomokuClaimed] — 음성 기준선: 일일 「1:1 오목」 한 줄만 받음으로(버튼 → "받음", 막대 초록). */
    private fun scene(dark: Boolean, gomokuClaimed: Boolean): @Composable () -> Unit {
        val achievements = if (!gomokuClaimed) MeScreenFixtures.achievements else MeScreenFixtures.achievements.let { json ->
            val at = json.indexOf("\"key\": \"daily_gomoku\"")
            val claimed = json.indexOf("\"claimed\": false", at)
            require(at >= 0 && claimed > at) { "픽스처에 일일 오목 줄이 없다" }
            json.substring(0, claimed) + "\"claimed\": true" + json.substring(claimed + "\"claimed\": false".length)
        }
        val s = store(achievements = achievements)
        return W4cDesktopSnapshots.frame(dark, W, H) { MeMissionsContent(s, scrolls = false) }
    }

    @Test fun missionsLight() = W4cDesktopSnapshots.check("missions", "missions-light", W, H, scene(false, false), scene(false, true))
    @Test fun missionsDark() = W4cDesktopSnapshots.check("missions", "missions-dark", W, H, scene(true, false), scene(true, true))

    /** 받기 연출 한 순간(떠오름 절반 · 아직 흐려지기 전). */
    @Test
    fun claimBurstFrame() {
        fun burst(progress: Float) = W4cDesktopSnapshots.frame(false, 160, 80) {
            Box(Modifier.padding(16.dp), contentAlignment = Alignment.Center) { MeClaimBurstView(5, serial = 1, reduceMotion = false, frozenProgress = progress) }
        }
        // 기준선: 같은 연출의 끝 무렵(0.95 — 흐려지는 꼬리 안). 알약 하나만 다르다.
        W4cDesktopSnapshots.check("missions", "claim-burst-light", 160, 80, burst(0.5f), burst(0.95f), maxChangedFraction = 0.5)
    }

    @Test
    fun sectionsAreInMacOrder() = runDesktopComposeUiTest(W, H) {
        val s = store()
        setContent { W4cDesktopSnapshots.frame(false, W, H) { MeMissionsContent(s, scrolls = false) }() }
        val daily = onNodeWithTag(MissionTags.DAILY).getBoundsInRoot()
        val weekly = onNodeWithTag(MissionTags.WEEKLY).getBoundsInRoot()
        val achievements = onNodeWithTag(MissionTags.ACHIEVEMENTS).getBoundsInRoot()
        assertTrue(daily.bottom <= weekly.top && weekly.bottom <= achievements.top, "순서가 일일 → 이번 주 → 누적이 아니다: $daily · $weekly · $achievements")
    }

    @Test
    fun dailyRowsFollowTheServer() {
        // 기준선: 서버가 여섯 줄을 주면 여섯 줄.
        assertEquals(6, dailyRows(MeScreenFixtures.achievements))
        // 서버가 일곱 번째 줄(길건너 아잉이 — 폰 1.0.14 바닥에도 '모두에게 보이기', G §8-18 7)을 주면 일곱 줄. 화면이 거르지 않는다.
        val seven = MeScreenFixtures.achievements.replacingOnce(
            """"key": "daily_tetris_duel",""",
            """"key": "daily_crossy", "game": "crossy", "title": "길건너 아잉이 한 판 하기", "detail": "", "reward": 5, "target": 1, "progress": 0,
            "achieved": false, "claimed": false, "claimed_at_ms": null, "sort": 70}, {"key": "daily_tetris_duel",""",
        )
        assertEquals(7, dailyRows(seven))
    }

    @Test
    fun missingDailyServerHidesTheDailyCard() {
        val withoutDaily = MeScreenFixtures.achievements.replacingOnce("\"daily\":", "\"daily_gone\":")
        var cards = -1
        var others = -1
        runDesktopComposeUiTest(W, H) {
            val s = store(achievements = withoutDaily)
            setContent { W4cDesktopSnapshots.frame(false, W, H) { MeMissionsContent(s, scrolls = false) }() }
            cards = onAllNodesWithTag(MissionTags.DAILY).fetchSemanticsNodes().size
            others = onAllNodesWithTag(MissionTags.WEEKLY).fetchSemanticsNodes().size + onAllNodesWithTag(MissionTags.ACHIEVEMENTS).fetchSemanticsNodes().size
        }
        assertEquals(0, cards, "일일 미션이 없는 서버인데 일일 카드가 섰다")
        assertEquals(2, others, "기준선: 이번 주 · 누적 카드는 그대로 선다")
    }

    /** 화면에 선 일일 줄 수(꼬리표가 "missions.row.daily_" 로 시작하는 마디 — 스토어 값으로 세지 않는다). */
    private fun dailyRows(achievements: String): Int {
        var n = -1
        runDesktopComposeUiTest(W, H) {
            val s = store(achievements = achievements)
            setContent { W4cDesktopSnapshots.frame(false, W, H) { MeMissionsContent(s, scrolls = false) }() }
            val prefix = MissionTags.row("daily_")
            n = onAllNodes(SemanticsMatcher("꼬리표가 $prefix 로 시작") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(prefix) == true }, useUnmergedTree = true)
                .fetchSemanticsNodes().size
        }
        return n
    }

    private companion object {
        const val W = 390
        const val H = 1640
    }
}
