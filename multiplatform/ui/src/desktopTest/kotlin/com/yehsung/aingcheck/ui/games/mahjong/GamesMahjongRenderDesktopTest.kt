// 원본: Tests/checkTests/V03xxMahjongPanelRenderTests.swift 의 뜻(판이 실제로 그려진다 — 패 · 펠트 · 손 칸) — Android 판 8.
// 그림은 빌드 폴더(ui/build/aingcheck-snapshots/desktop/mahjong-*.png)에만 쓴다 — 골든 비교가 아니라 사람이 볼 렌더와 '빈 화면이 아니다' 단언.
package com.yehsung.aingcheck.ui.games.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStore
import com.yehsung.aingcheck.core.stores.mahjong.startPractice
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.Job
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class GamesMahjongRenderDesktopTest {
    // 없으면: 패 그리기(통 · 삭 · 글자 · 뒷면)나 가로 판 배치가 깨져 빈 펠트만 나와도 상호작용 시험은 초록이다.
    @Test
    fun practiceTableRendersTilesOnFelt() {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val mahjong = MahjongStore(null, h.storeScope, clock = { SwiftDate(1_800_000_000.0) }, botContext = h.storeScope.coroutineContext.minusKey(Job))
        mahjong.timersEnabled = false
        mahjong.practiceRuntime.delayScale = 0.0
        mahjong.practiceRuntime.pickHumanSeat = { 1 }
        mahjong.practiceRuntime.makeWall = { (0 until 136).shuffled(kotlin.random.Random(11)) }
        mahjong.practiceRuntime.nextSeed = { 5uL }
        h.mahjong = mahjong
        val games = GamesStore(h.context)
        games.appDidBecomeActive()
        games.mahjongScreenDidAppear()
        mahjong.startPractice(MahjongFormat.tonpuu, timed = false)
        h.testScope.advanceUntilIdle()
        val image = DesktopSnapshots.render(852, 393) { AingTheme(dark = true) { GamesMahjongTableView(games, mahjong, "나", null, onRules = {}, onLeaveTable = {}) } }
        DesktopSnapshots.writePng(image, File(DesktopSnapshots.outDir(), "mahjong-table-practice.png"))
        // 펠트 · 손 칸 · 패 몸체 크림색이 모두 있어야 한다(빈 화면 · 펠트만이 아니다).
        val cream = image.argb.count { p -> ((p shr 16) and 0xFF) > 230 && ((p shr 8) and 0xFF) > 225 && (p and 0xFF) > 240 }
        val felt = image.argb.count { p -> val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF; r in 50..70 && g in 90..110 && b in 82..102 }
        assertTrue(cream > 5_000, "패 몸체가 안 보인다($cream)")
        assertTrue(felt > 20_000, "펠트가 안 보인다($felt)")
        val lobby = DesktopSnapshots.render(393, 852) {
            AingTheme(dark = false) { GamesMahjongScreen(games, MahjongStore(null, h.storeScope, clock = { SwiftDate(1_800_000_000.0) }), "나", null) }
        }
        DesktopSnapshots.writePng(lobby, File(DesktopSnapshots.outDir(), "mahjong-lobby.png"))
        h.close()
    }
}
