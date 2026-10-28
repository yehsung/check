// 원본: Tests/CheckMobileKitTests/MeDesignContractTests.swift @ 3bd04bd (나 탭 루트 배치 계약 · MeAnchor 이름) · Sources/CheckMobileShared/AILimitColumnStyle.swift(값 계약)
package com.yehsung.aingcheck.ui.screens.me

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.stores.me.AILimitFetchedRow
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeLoadState
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.components.CharacterMood
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MeHomeRulesTest {
    @Test
    fun presenceUsesNowCardThenSnapshotElseUnknown() {
        val card = NowMyCard(isWorking = true, isStale = false, sessionStartedAt = null, todaySeconds = 0, weekSeconds = 0, goalHours = 40)
        assertEquals(MeStageMood.working, MeHomeRules.presence(card, MeStageMood.off), "지금 탭 카드가 이긴다")
        assertEquals(MeStageMood.lost, MeHomeRules.presence(card.copy(isStale = true)))
        assertEquals(MeStageMood.off, MeHomeRules.presence(card.copy(isWorking = false)))
        assertEquals(MeStageMood.off, MeHomeRules.presence(null, MeStageMood.off), "카드가 없으면 스냅숏")
        assertNull(MeHomeRules.presence(null, null), "모르면 null — 지어내지 않는다")
        assertEquals(listOf(CharacterMood.Working, CharacterMood.Lost, CharacterMood.Off, CharacterMood.Plain, null),
            listOf(MeStageMood.working, MeStageMood.lost, MeStageMood.off, MeStageMood.plain, null).map(MeHomeRules::characterMood))
    }

    @Test
    fun identityNameNeverPromotesEmailBeforeProfileLoaded() {
        assertEquals("새벽", MeHomeRules.identityName("새벽", headerLoaded = false, email = "a@b.co"))
        assertEquals("나", MeHomeRules.identityName(null, headerLoaded = false, email = "a@b.co"), "못 받은 채 이메일을 제목으로 세우지 않는다(E-me)")
        assertEquals("a@b.co", MeHomeRules.identityName(null, headerLoaded = true, email = "a@b.co"))
        assertEquals("나", MeHomeRules.identityName(null, headerLoaded = true, email = null))
    }

    @Test
    fun wearLineAndHeaderRetry() {
        assertEquals("여우 착용 중" to MeWearKind.Value, MeHomeRules.wearLine(true, false, "fox"))
        assertEquals("착용 정보를 불러오지 못했어요" to MeWearKind.Failed, MeHomeRules.wearLine(false, true, "aing"))
        assertEquals("불러오는 중…" to MeWearKind.Loading, MeHomeRules.wearLine(false, false, "aing"))
        val failedNever = MeLoadState().apply { hasFailed = true }
        assertTrue(MeHomeRules.showsHeaderRetry(failedNever))
        val failedAfterLoad = MeLoadState().apply { hasFailed = true; hasLoaded = true }
        assertTrue(!MeHomeRules.showsHeaderRetry(failedAfterLoad), "받은 값이 있으면 다시 시도 줄을 세우지 않는다")
    }

    @Test
    fun recordsPhaseAndRhythmCaption() {
        assertEquals(MeRecordsPhase.Loading, MeHomeRules.recordsPhase(MeLoadState()))
        assertEquals(MeRecordsPhase.Failed, MeHomeRules.recordsPhase(MeLoadState().apply { hasFailed = true }))
        assertEquals(MeRecordsPhase.Ready, MeHomeRules.recordsPhase(MeLoadState().apply { hasLoaded = true; hasFailed = true }), "받은 값이 있으면 준비됨")
        assertEquals("불러오는 중…", MeHomeRules.rhythmCaption(MeRecordsPhase.Loading, WorkRhythmHeatmap.empty))
        assertEquals("기록을 불러오지 못했어요", MeHomeRules.rhythmCaption(MeRecordsPhase.Failed, WorkRhythmHeatmap.empty))
        assertEquals("지난주 근무 기록이 없어요", MeHomeRules.rhythmCaption(MeRecordsPhase.Ready, WorkRhythmHeatmap.empty))
        // 격자 치수(Swift MeRhythmMetrics): 361 폭 = (361 − 18 − 2×23)/24 = 12.375 · 상한 13 · 하한 3.
        assertEquals(12.375f, MeRhythmMetrics.cellSize(361f))
        assertEquals(13f, MeRhythmMetrics.cellSize(2000f))
        assertEquals(3f, MeRhythmMetrics.cellSize(10f))
        assertEquals(15f + 12.375f * 7 + 2f * 6, MeRhythmMetrics.height(361f))
    }

    @Test
    fun menuAndMissionsRow() {
        val rows = MeHomeRules.menuRows(hasUnseenFeedbackReply = true)
        assertEquals(listOf(MeDestination.Profile, MeDestination.Feedback, MeDestination.Settings), rows.map { it.destination })
        assertEquals(listOf("프로필", "제보", "설정"), rows.map { it.title })
        assertEquals(listOf(false, true, false), rows.map { it.showsReply }, "답장 배지는 제보 행에만")
        assertEquals("받을 보상 2개" to true, MeHomeRules.missionsTrailing(2))
        assertEquals("일일 · 이번 주 · 누적 미션" to false, MeHomeRules.missionsTrailing(0))
    }

    /** 스크린샷 명령이 쓰는 앵커 이름(Swift MeAnchor rawValue)이 같다 — 바꾸면 저장소 밖 스크립트가 깨진다(MeDesignContractTests). */
    @Test
    fun anchorNamesMatchSwift() {
        val swift = RepoFiles.readText("Sources/CheckMobileKit/Me/MeTab.swift")
        val enumBody = swift.substringAfter("enum MeAnchor: String {").substringBefore("\n}")
        val names = Regex("""case ([a-zA-Z, ]+)""").findAll(enumBody).flatMap { m -> m.groupValues[1].split(',').map { it.trim() } }.filter { it.isNotEmpty() }.toSet()
        assertEquals(names, MeAnchor.entries.map { it.raw }.toSet())
    }

    /** 열 색·단계·채움 산식이 Swift 공유 모듈 값과 같다(원문을 제자리에서 읽는다 — 손으로 옮긴 값의 오타를 잡는다). */
    @Test
    fun aiLimitStyleConstantsMatchSwift() {
        val style = RepoFiles.readText("Sources/CheckMobileShared/AILimitColumnStyle.swift")
        assertTrue(style.contains("warnPercent = ${AILimitUsageStage.warnPercent}") && style.contains("dangerPercent = ${AILimitUsageStage.dangerPercent}"))
        assertTrue(style.contains("max(2, barWidth * 0.08)"), "최소 채움 산식이 바뀌었다")
        val surface = RepoFiles.readText("Sources/CheckMobileShared/AILimitSurfaceRules.swift")
        assertTrue(surface.contains("floorOpacity: Double = ${AILimitFloorFill.floorOpacity}"))
        // 채움 폭(같은 입력 → Swift 산식의 손 계산 값).
        assertEquals(0.0, AILimitBarFill.width(40.0, null), "모르면 채움 없음")
        assertEquals(0.0, AILimitBarFill.width(40.0, 0.0), "0% 는 0")
        assertEquals(3.2, AILimitBarFill.width(40.0, 1.0), "1% 도 8% 만큼 보인다")
        assertEquals(20.0, AILimitBarFill.width(40.0, 50.0))
        assertEquals(40.0, AILimitBarFill.width(40.0, 140.0), "100 을 넘지 않는다")
        assertEquals(AILimitUsageStage.calm, AILimitUsageStage.stage(null), "모르는 값에 경고를 붙이지 않는다")
        assertEquals(AILimitUsageStage.warn, AILimitUsageStage.stage(70))
        assertEquals(AILimitUsageStage.danger, AILimitUsageStage.stage(90))
    }

    /** 맥 두 대·이름 겹침 묶음은 스토어 두 함수를 지난다 — 꼬리는 이름과 따로 실린다(INV-MeAILimitsCard-54a8727b). */
    @Test
    fun twinDeviceGroupsCarryTailSeparately() {
        val now = SwiftDate(1_789_621_500.0)
        fun row(device: String, label: String?, provider: String, ago: Double) = AILimitFetchedRow(
            device, label, provider, 27.0, SwiftDate(now.timeIntervalSince1970 + 9_000), 60.0, SwiftDate(now.timeIntervalSince1970 + 450_000), "max",
            SwiftDate(now.timeIntervalSince1970 - ago),
        )
        val groups = MeAILimitsScenes.fold(listOf(row("twin-aaaa-a1b2", "Mac mini", "claude", 120.0), row("twin-bbbb-c3d4", "Mac mini", "claude", 600.0)), now)
        assertEquals(2, groups.size)
        assertTrue(groups.all { it.nameParts.base == "Mac mini" && it.nameParts.tail != null }, "같은 이름 둘이면 둘 다 꼬리: ${groups.map { it.nameParts }}")
        assertTrue(groups[0].nameParts.tail != groups[1].nameParts.tail)
        assertEquals("Mac mini (${groups[0].nameParts.tail})", groups[0].name)
        assertEquals("(A1B2)", AILimitDeviceNameParts.tailText("A1B2"))
    }
}
