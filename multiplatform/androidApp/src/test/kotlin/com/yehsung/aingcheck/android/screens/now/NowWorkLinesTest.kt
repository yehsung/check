// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (NowWorkControlRow.lines · NowStatusCard.mood/subtitle · NowWorkingRow.elapsed)
package com.yehsung.aingcheck.android.screens.now

import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.stores.now.NowWorkingPerson
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.CharacterMood
import org.junit.Assert.assertEquals
import org.junit.Test

class NowWorkLinesTest {
    @Test
    fun linesUnderTheButton() {
        assertEquals(listOf(NowText.workNeedsTeam), NowWorkLines.lines(hasNoTeam = true, working = false, origin = NowWorkOrigin.unknown, checkAfterSeconds = null))
        assertEquals(emptyList<String>(), NowWorkLines.lines(false, working = false, origin = NowWorkOrigin.phone, checkAfterSeconds = 9000))
        assertEquals(listOf(NowText.phoneWorkCaption(5400)), NowWorkLines.lines(false, true, NowWorkOrigin.phone, 5400))
        assertEquals(listOf(NowText.macWorkCaption), NowWorkLines.lines(false, true, NowWorkOrigin.mac, null))
        assertEquals(emptyList<String>(), NowWorkLines.lines(false, true, NowWorkOrigin.unknown, null))
        assertEquals("Windows 가 연 근무를 맥 안내로 접었다(int-j)", emptyList<String>(), NowWorkLines.lines(false, true, NowWorkOrigin.windows, null))
    }

    @Test
    fun cardMoodAndSubtitle() {
        val started = SwiftDate(1_789_610_400.0) // 11:00 KST
        val working = NowMyCard(true, false, started, 3600, 7200, 40)
        assertEquals(CharacterMood.Working, NowWorkLines.mood(working))
        assertEquals(NowText.sessionSince("11:00"), NowWorkLines.subtitle(working))
        val stale = working.copy(isStale = true)
        assertEquals(CharacterMood.Lost, NowWorkLines.mood(stale))
        assertEquals(NowText.staleSubtitle, NowWorkLines.subtitle(stale))
        val off = NowMyCard(false, false, null, 0, 0, 40)
        assertEquals(CharacterMood.Off, NowWorkLines.mood(off))
        assertEquals(NowText.offSubtitle, NowWorkLines.subtitle(off))
    }

    @Test
    fun teammateElapsed() {
        val now = SwiftDate(1_789_621_500.0)
        val live = NowWorkingPerson("a", "가", null, null, true, SwiftDate(now.timeIntervalSince1970 - 5_400), null, false)
        assertEquals(5_400, NowWorkingElapsed.seconds(live, now))
        // 끊긴 사람은 스토어가 멈춘 값(시작 시각에서 세지 않는다).
        val stale = live.copy(isStale = true, elapsedSeconds = 1_200)
        assertEquals(1_200, NowWorkingElapsed.seconds(stale, now))
        assertEquals(0, NowWorkingElapsed.seconds(live.copy(startedAt = SwiftDate(now.timeIntervalSince1970 + 60)), now))
    }
}
