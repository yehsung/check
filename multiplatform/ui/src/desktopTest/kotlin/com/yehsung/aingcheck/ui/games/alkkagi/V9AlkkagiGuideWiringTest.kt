// 원본: Tests/CheckMobileKitTests/V1019AlkkagiGuideTests.swift(wiring) @ faba845a
package com.yehsung.aingcheck.ui.games.alkkagi

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 판 9 — 알까기 안내 배선: 판이 내 칸 그림 · 초록 고리 · 손 안내 · 가운데 띠를 그리고 · 횟수를 기기 설정에 · 로비 첫 카드 · 상태 상자. 주석을 걷고 본다. */
class V9AlkkagiGuideWiringTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private fun code(rel: String) = SwiftStyleComments.strip(File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/games/alkkagi/$rel").readText()).filter { !it.isWhitespace() }

    @Test
    fun boardLobbyAndStatusAreWired() {
        val board = code("GamesAlkkagiBoard.kt")
        assertTrue(board.contains("GamesAlkkagiGuideDrawing.zones(this,placingPlayer,accent,measurer)"))
        assertTrue(board.contains("if(model.guideIsMyAim)GamesAlkkagiGuideDrawing.myStones("))
        assertTrue(board.contains("model.pullHintStone?.let{hint->GamesAlkkagiPullHint(hint,model.guideSide,reduceMotion,side)}"))
        assertTrue(board.contains("model.guideBandText?.let{text->"))
        assertFalse(board.contains("accent.copy(alpha=0.12f)"), "옛 반쪽 칠하기가 남았다")
        val match = code("GamesAlkkagiMatch.kt")
        assertTrue(match.contains("model.guidePrefs=guidePrefs"), "손 안내 횟수를 기기 설정에 기억하지 않는다")
        assertTrue(match.contains("GamesAlkkagiStatusBox(text,tint,"))
        assertTrue(match.contains("GamesAlkkagiStatusBox(model.notice?:model.status,practiceTint,"))
        val screen = code("GamesAlkkagiScreen.kt")
        assertTrue(screen.contains("if(AlkkagiPhoneFirstTimeCoach.shows(coachSeen)){GamesAlkkagiCoachCard("))
        assertTrue(screen.contains("prefs.putBoolean(AlkkagiPhoneFirstTimeCoach.seenKey,true)"))
        assertTrue(screen.contains("guidePrefs=store.context.keyValueStore"))
    }
}
