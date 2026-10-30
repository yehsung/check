// 원본: Sources/check/TetrisDuelPanel.swift:1086-1093(`case .ready where store.playingElsewhere` → MiniGameOverlayCard
//       TetrisDuelNoticeText.otherDevice · otherDeviceSubtitle · otherDeviceAction · "macbook.and.iphone") · :145-146(문구)
//       · TetrisDuelPanel.swift:960-981(덮개 아래 판은 빈 판 placeholder — 구동기 없음) · CheckCore TetrisDuelStore.swift:355
//       (vc3 한 판 한 기기 — check 개발 부탁 ②: Windows 대결 창의 '다른 기기에서 대결 중' 카드)
//
// Windows 대결 창은 공용 세로 화면(GamesTetrisDuelScreen → GamesTetrisDuelMatchView BoardOverlay)을 GameWindowFrame 에 그대로 싣는다.
// 공용 BoardOverlay 가 이미 그 카드를 그린다(Stage.waiting where playingElsewhere — 맥 .ready where 와 같은 단계: 구동기가 없으면
// refreshPhase 가 언제나 ready 를 낸다). 그래서 데스크톱은 덮개를 더하지 않고 **실제 창 트리**에서 잰다:
//   · my_device='other' 판(서버에선 이미 시작) → 카드 제목·부제·행동 문구가 보인다 · 구동기 0 · 창 키(실제 duelKeys 라우터)·스토어 입력 → tetris_report 0.
//   · my_device='this' 같은 판 → 카드 0 · 구동기 있음 · 창이 보이고 틱이 돌면 보고가 나간다(세는 눈이 보고를 볼 수 있다는 양성 대조).
@file:OptIn(ExperimentalTestApi::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.windows.games.tetris

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelNoticeText
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.core.stores.tetris.hardDrop
import com.yehsung.aingcheck.core.stores.tetris.rotate
import com.yehsung.aingcheck.core.stores.tetris.setLeftHeld
import com.yehsung.aingcheck.core.stores.tetris.tick
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.desktop.windows.games.minigame.ComposeGamesWindows
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import com.yehsung.aingcheck.ui.games.minigame.UiFixtures
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.games.tetris.TetrisDuelTags
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** 합성 판 상태(맥 TDServer 꼴 — 옛·새 서버 모두). [myDevice] null 이면 칸이 없다(옛 서버). */
internal object TetrisOtherDeviceFixture {
    const val MATCH = "7e7e0000-0000-4000-8000-0000000000c3"
    const val NOW_MS: Long = 1_789_621_500_000
    const val PEER = "bbbbbbbb-0000-4000-8000-000000000002"
    val ME: String get() = UiFixtures.USER

    fun stateJson(myDevice: String?, started: Boolean, peerName: String = "라이벌"): String =
        """{"match_id":"$MATCH","status":"active","stake":3,"seed":4242,"server_now_ms":$NOW_MS,"accepted_at_ms":${NOW_MS - 2_000},""" +
            (if (started) """"start_at_ms":${NOW_MS - 1_000},"max_end_ms":${NOW_MS + 479_000},""" else "") +
            """"ready_deadline_ms":${NOW_MS + 28_000},""" +
            """"me":{"id":"$ME","display_name":"나","ready":$started,"seq":0},""" +
            """"opponent":{"id":"$PEER","display_name":"$peerName","ready":true,"seq":0},"ruby_balance":97""" +
            (myDevice?.let { ""","my_device":"$it"""" } ?: "") + "}"

    fun state(myDevice: String?, started: Boolean, peerName: String = "라이벌"): TetrisStatePayload =
        SwiftJson.decode(TetrisStatePayload.serializer(), stateJson(myDevice, started, peerName))
}

class TetrisOtherDeviceCardTest {
    private data class Seen(
        val titles: Int,
        val subtitles: Int,
        val actions: Int,
        val boards: Int,
        val hasDriver: Boolean,
        val phase: TetrisDuelPhase,
        val playingElsewhere: Boolean,
        val reports: Int,
        val keysSwallowed: Int,
    )

    private fun route(myDevice: String): (RecordedRequest) -> Pair<String, Int>? = { r ->
        val f = TetrisOtherDeviceFixture
        when (r.rpcName) {
            "tetris_report" -> """{"status":"ok","state":${f.stateJson(myDevice, started = true)},"server_now_ms":${f.NOW_MS}}""" to 200
            "tetris_state" -> """{"status":"ok","state":${f.stateJson(myDevice, started = true)},"server_now_ms":${f.NOW_MS}}""" to 200
            "tetris_lobby" -> """{"status":"ok","server_now_ms":${f.NOW_MS},"me":{"ruby_balance":97,"wins":0,"losses":0,"draws":0,"incoming":[]},"users":[],"matches":[]}""" to 200
            else -> null
        }
    }

    /** 실제 창 트리(TetrisDuelWindowContent = GameWindowFrame + 공용 화면)에 서버가 이미 시작한 판을 넣고 글자를 센 뒤, 창이 보이고 틱·키가 돈 다음 보고를 센다. */
    private fun scene(myDevice: String): Seen {
        var out: Seen? = null
        runDesktopComposeUiTest(440, 720) {
            val test = TestScope()
            val h = UiGamesHarness(test, AppConfig(duelsEnabled = true), route(myDevice))
            h.tetris.uptime = { 1_000.0 }
            runBlocking { h.signIn() }
            h.tetris.applyState(TetrisOtherDeviceFixture.state(myDevice, started = true), receivedAt = 1_000.0)
            val games = GamesStore(h.context)
            val doors = TetrisDuelWindowDoors(h.tetris)
            val window = TetrisDuelWindowState(doors)
            setContent {
                TetrisDuelWindowContent(games, window, myUserID = UiFixtures.USER, meName = null, dark = false, reduceMotion = true, onBack = {})
            }
            waitForIdle()
            // 글자는 창이 뜨기 **전에** 센다 — 이 기기 판('this')은 창이 뜨고 판이 흐르면 프레임마다 다시 그려 waitForIdle 이 끝나지 않는다.
            val notice = TetrisDuelNoticeText.otherDevice
            val titles = onAllNodesWithText(notice, useUnmergedTree = true).fetchSemanticsNodes().size
            val subtitles = onAllNodesWithText(SUBTITLE, useUnmergedTree = true).fetchSemanticsNodes().size
            val actions = onAllNodesWithText(ACTION, useUnmergedTree = true).fetchSemanticsNodes().size
            val boards = onAllNodesWithTag(TetrisDuelTags.BOARD, useUnmergedTree = true).fetchSemanticsNodes().size
            // 창이 화면에 떴다 → 준비(첫 보고)가 설 자리. 틱 몇 번 · 창 키(실제 대결 라우터) · 스토어 입력을 곧바로도 넣는다.
            doors.windowDidShow()
            val keys = ComposeGamesWindows.duelKeys(games)
            var swallowed = 0
            for (vk in listOf(GameKeyMap.VK_LEFT, GameKeyMap.VK_RIGHT, GameKeyMap.VK_SPACE, GameKeyMap.VK_UP)) {
                if (keys.route(vk, down = true, hasModifiers = false, isRepeat = false, ownsKeys = true)) swallowed++
                keys.route(vk, down = false, hasModifiers = false, isRepeat = false, ownsKeys = true)
            }
            h.tetris.setLeftHeld(true)
            h.tetris.setLeftHeld(false)
            h.tetris.rotate(clockwise = true)
            h.tetris.hardDrop()
            for (step in 1..4) {
                h.tetris.uptime = { 1_000.0 + step }
                h.tetris.tick()
                test.testScheduler.advanceUntilIdle()
            }
            out = Seen(
                titles = titles,
                subtitles = subtitles,
                actions = actions,
                boards = boards,
                hasDriver = h.tetris.duel != null,
                phase = h.tetris.phase,
                playingElsewhere = h.tetris.playingElsewhere,
                reports = h.server.count("tetris_report"),
                keysSwallowed = swallowed,
            )
            h.tetris.reset()
            h.close()
        }
        return requireNotNull(out)
    }

    @Test
    fun anotherDevicesMatchShowsTheCardAndTakesNoInput() {
        val seen = scene("other")
        // 맥 TetrisDuelPanel.swift:1088 — 단계는 ready(구동기가 없으면 서버가 이미 시작한 판도 ready 다) ∧ playingElsewhere.
        assertEquals(TetrisDuelPhase.ready, seen.phase, "$seen")
        assertTrue(seen.playingElsewhere, "$seen")
        assertEquals(1, seen.titles, "제목 '${TetrisDuelNoticeText.otherDevice}' 이 한 번 보여야 한다(밑 안내 줄과 겹치지 않게): $seen")
        assertEquals(1, seen.subtitles, "부제가 없다: $seen")
        assertEquals(1, seen.actions, "행동 문구가 없다: $seen")
        // 판 자리는 빈 판(placeholder) — 구동기가 없다(맥 :968 `store.duel?.game ?? placeholder`).
        assertEquals(1, seen.boards, "판 자리가 없다(덮개가 설 곳): $seen")
        assertEquals(false, seen.hasDriver, "다른 기기 판에 구동기를 세웠다: $seen")
        assertEquals(0, seen.keysSwallowed, "판 흐름 밖(ready)인데 창이 키를 삼켰다: $seen")
        assertEquals(0, seen.reports, "다른 기기 판에서 tetris_report 가 나갔다: $seen")
    }

    @Test
    fun thisDevicesMatchHasNoCardAndItsReportsAreSeen() {
        val seen = scene("this")
        assertEquals(0, seen.titles + seen.subtitles + seen.actions, "이 기기 판에 다른 기기 카드가 떴다: $seen")
        assertTrue(seen.hasDriver, "이 기기 판에 구동기가 없다: $seen")
        assertTrue(seen.phase == TetrisDuelPhase.playing || seen.phase == TetrisDuelPhase.countdown, "$seen")
        // 양성 대조: 같은 눈이 이 기기 판의 보고는 본다 — 위 '0' 이 세는 눈이 먼 탓이 아니다.
        assertTrue(seen.reports > 0, "이 기기 판인데 보고 0 — 세는 눈이 보고를 못 본다: $seen")
        assertTrue(seen.keysSwallowed > 0, "판 중인데 창 키를 안 받았다: $seen")
    }

    private companion object {
        // 맥 TetrisDuelPanel.swift:145-146 글자 그대로(공용 TetrisPhoneText 가 아니라 원본을 적는다 — 두 벌이 갈라지면 빨강).
        const val SUBTITLE = "신청하거나 수락한 기기에서만 둘 수 있어요"
        const val ACTION = "그 기기에서 이어 가세요"
    }
}
