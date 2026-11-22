// 원본: Tests/CheckMobileKitTests/V1019AlkkagiGuideTests.swift @ faba845a (폰 1.0.19 — 알까기 안내 · 맥 0.3.86 C안의 폰 짝)
package com.yehsung.aingcheck.core.stores.alkkagi

import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.stores.games.MemoryPrefs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 알까기 안내(대표 #d_xygj8oZRFlfH 5번 · 대표 11-10 "어디다 돌 둬야되는지 … 뭘 하라는건지 모르겠어"). */
class V9AlkkagiGuideTest {
    @Test
    fun zoneMatchesCanPlace() {
        val game = AlkkagiGame.newGame()
        val black = game.stones.first { it.owner == AlkkagiGame.Player.black }
        assertTrue(game.canPlace(black.id, AlkkagiVector(300.0, AlkkagiPhoneGuideGeometry.blackZoneTop)))
        assertFalse(game.canPlace(black.id, AlkkagiVector(300.0, AlkkagiPhoneGuideGeometry.blackZoneTop - 0.5)))
        for (x in listOf(80.0, 190.0, 300.0, 410.0, 520.0)) {
            val id = game.stones.first { it.owner == AlkkagiGame.Player.black && !it.isPlaced }.id
            game.placeStone(id, AlkkagiVector(x, 470.0))
        }
        game.confirmPlacement()
        val white = game.stones.first { it.owner == AlkkagiGame.Player.white }
        assertEquals(AlkkagiGame.Player.white, game.currentPlayer)
        assertTrue(game.canPlace(white.id, AlkkagiVector(300.0, AlkkagiPhoneGuideGeometry.whiteZoneBottom)))
        assertFalse(game.canPlace(white.id, AlkkagiVector(300.0, AlkkagiPhoneGuideGeometry.whiteZoneBottom + 0.5)))
    }

    @Test
    fun copyMatchesMacAndIPhone() {
        val b = AlkkagiGame.Player.black
        val w = AlkkagiGame.Player.white
        assertEquals("내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 2/5", AlkkagiPhoneGuideText.band(b, 2))
        assertEquals("내 진영(위 파란 칸)에 돌 5개를 놓으세요 · 0/5", AlkkagiPhoneGuideText.band(w, 0))
        assertEquals("아래 파란 칸에 내 돌 5개를 놓으세요 (3/5)", AlkkagiPhoneGuideText.placing(b, 3, null))
        assertEquals("백돌 차례 — 위 파란 칸에 돌 5개를 놓으세요 (1/5)", AlkkagiPhoneGuideText.placing(w, 1, w))
        assertEquals("준비 완료 — 상대가 놓기를 기다려요", AlkkagiPhoneGuideText.placedWaiting)
        assertEquals("파란 칸 안에, 다른 돌과 겹치지 않게 놓아 주세요", AlkkagiPhoneGuideText.placeRejected)
        assertEquals("영희님이 쏠 차례예요 — 기다려 주세요", AlkkagiPhoneGuideText.opponentTurn("영희"))
        assertEquals("내 차례 — 내 돌을 뒤로 당겼다 놓으세요", AlkkagiPhoneGuideText.aiming(null, holding = false, firstShotLimited = false))
        assertEquals("내 차례 — 내 돌을 뒤로 당겼다 놓으세요 (첫 수는 힘 60%까지)", AlkkagiPhoneGuideText.aiming(null, holding = false, firstShotLimited = true))
        assertEquals("놓으면 반대쪽으로 날아가요 · 돌 위로 되돌리면 취소", AlkkagiPhoneGuideText.aiming(null, holding = true, firstShotLimited = false))
        assertFalse(AlkkagiPhoneGuideText.aiming(null, holding = true, firstShotLimited = true).contains("Esc"), "폰에 Esc 가 없다")
        assertEquals("뒤로 당겼다 놓기", AlkkagiPhoneGuideText.handHint)
        assertEquals(
            listOf("파란 칸(내 진영)에 내 돌 5개를 숨겨 놓아요", "내 차례가 오면 내 돌을 뒤로 당겼다 놓아요", "상대 돌을 판 밖으로 모두 밀어내면 이겨요"),
            AlkkagiPhoneFirstTimeCoach.steps.map { it.title },
        )
        assertTrue(AlkkagiPhoneFirstTimeCoach.shows(false) && !AlkkagiPhoneFirstTimeCoach.shows(true))
    }

    @Test
    fun pullHintCountsThreeShotsAndRemembers() {
        val model = GamesAlkkagiBoardModel()
        val prefs = MemoryPrefs()
        model.guidePrefs = prefs
        fun place(x: Double, y: Double) {
            model.aim(AlkkagiVector(x, y), AlkkagiVector(0.0, 0.0))
            model.release()
        }
        assertNull(model.pullHintStone)
        assertEquals("내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 0/5", model.guideBandText)
        for (x in listOf(80.0, 190.0, 300.0, 410.0, 520.0)) place(x, 470.0)
        assertEquals("내 진영(아래 파란 칸)에 돌 5개를 놓으세요 · 5/5", model.guideBandText)
        model.confirmPlacement()
        assertEquals("내 진영(위 파란 칸)에 돌 5개를 놓으세요 · 0/5", model.guideBandText, "연습 판은 지금 놓는 쪽")
        for (x in listOf(80.0, 190.0, 300.0, 410.0, 520.0)) place(x, 130.0)
        model.confirmPlacement()
        assertEquals(AlkkagiGame.Phase.aiming, model.game.phase)
        assertNull(model.guideBandText)
        assertTrue(model.guideIsMyAim)
        assertEquals(300.0, model.pullHintStone?.position?.x, "가운데 돌(x 300)에 손이 붙는다")
        // 돌을 잡으면 손 안내는 사라진다.
        model.aim(AlkkagiVector(300.0, 470.0), AlkkagiVector(0.0, 40.0))
        assertNull(model.pullHintStone)
        assertFalse(model.guideIsMyAim)
        var now = 1_000.0
        fun settle() {
            model.tick(now)
            var n = 0
            while (model.game.phase == AlkkagiGame.Phase.rolling && n < 900) {
                now += 1.0 / 60
                model.tick(now)
                n++
            }
        }
        model.release()
        settle()
        assertEquals(1, model.pullHintShots)
        assertEquals(1L, prefs.getLong(GamesAlkkagiBoardModel.PULL_HINT_SHOTS_KEY))
        var guard = 0
        while (model.game.phase == AlkkagiGame.Phase.aiming && guard < 4) {
            val stone = model.game.stones.firstOrNull { it.owner == model.game.currentPlayer && it.isPlaced && !it.isOut } ?: break
            model.aim(stone.position, AlkkagiVector(0.0, if (stone.position.y > 300) 40.0 else -40.0))
            model.release()
            settle()
            guard++
        }
        assertEquals(GamesAlkkagiBoardModel.PULL_HINT_SHOT_LIMIT, model.pullHintShots, "세 번에서 멈춘다")
        assertNull(model.pullHintStone, "세 번 쏜 뒤에도 손이 나온다")
        // 새 판(같은 기기)도 기억한 수를 읽는다.
        val fresh = GamesAlkkagiBoardModel()
        fresh.guidePrefs = prefs
        assertEquals(GamesAlkkagiBoardModel.PULL_HINT_SHOT_LIMIT, fresh.pullHintShots)
    }

    @Test
    fun pullHintPhaseBeats() {
        assertEquals(0.0, AlkkagiPhoneGuideGeometry.pullHintPhase(0.0).first)
        assertEquals(1.0 to 0.0, AlkkagiPhoneGuideGeometry.pullHintPhase(0.95))
        val release = AlkkagiPhoneGuideGeometry.pullHintPhase(1.2)
        assertTrue(release.first == 0.0 && release.second == 1.0)
        assertTrue(AlkkagiPhoneGuideGeometry.pullHintPhase(2.45).first > 0.3)
    }
}
