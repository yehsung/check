// 원본: 없음 — 설계서 §10 가로 판 화면의 스냅숏(iOS 는 데모 라우트 games/rummy/match/* 시뮬레이터 캡처). 하네스는 W4cDesktopSnapshots(세 판정 — 굳은 렌더 · 골든 · 음성 기준선).
//
// 판에 묶음이 있고 받침대 2줄이 찬 장면을 852×393 에서 찍는다. 칸 자리가 움직이면 이 그림이 먼저 빨개진다. 값의 판정은 GamesRummyBoardGeometryTest · GamesRummyMatchInteractionTest.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.shop.W4cDesktopSnapshots
import androidx.compose.runtime.Composable
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test

internal object GamesRummyMatchScene {
    private const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
    private const val USER = "7e7e0000-0000-4000-8000-0000000000a1"
    private const val NOW_MS = 1_800_000_000_000L
    private val NOW = SwiftDate(1_800_000_000.0)
    private val ME = RummySeatFace("나", null, null)
    const val W = 852
    const val H = 393

    private const val TABLE = """[["A1","A2","A3","A4"],["B7","C7","D7"],["C9","C10","C11","C12","C13"],["D1","D2","D3"],["A10","B10","C10"],["B3","B4","B5","B6"]]"""
    private const val LAYOUT = "[[40,16],[260,16],[480,16],[760,16],[40,120],[260,120]]"

    /** 16장 + 8장 — 받침대 2줄이 찬다. */
    private const val RACK = """["A5","A6","A7","A8","A9","A10","A11","A12","A13","B1","B2","B3","B4","B5","B6","B8","C1","C2","C3","D10","D11","D12","D13","J"]"""

    fun state(rack: String = RACK, turnSeat: Int = 0, table: String = TABLE, layout: String = LAYOUT): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"active","host_id":"$USER","stake":5,"seat_count":4,"seq":3,"pool_count":41,"server_now_ms":$NOW_MS,""" +
            """"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"playing","rack_count":24,"initial_done":true},""" +
            """{"seat_no":1,"user_id":"7e7e0000-0000-4000-8000-0000000000b2","display_name":"구름","state":"playing","rack_count":9,"initial_done":true,"timeout_streak":1},""" +
            """{"seat_no":2,"user_id":"7e7e0000-0000-4000-8000-0000000000b3","display_name":"긴이름의사람입니다","state":"playing","rack_count":14,"initial_done":false},""" +
            """{"seat_no":3,"user_id":"7e7e0000-0000-4000-8000-0000000000b4","display_name":"소라","state":"forfeit","rack_count":3,"initial_done":true}],""" +
            """"my_seat_no":0,"my_rack":$rack,"my_initial_done":true,"table":$table,"table_layout":$layout,"turn_seat_no":$turnSeat,""" +
            """"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 42_000},"grace_ms":2000,"last_event":{"kind":"play","seat_no":3,"count":3}}""",
    )

    fun rig(state: RummyMatchState = state()): Pair<UiGamesHarness, RummyStore> {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val rummy = RummyStore(h.storeScope).also {
            it.clock = { NOW }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
        }
        rummy.applyState(state)
        rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        return h to rummy
    }

    fun frame(dark: Boolean, state: RummyMatchState = state(), w: Int = W, h: Int = H, reduceMotion: Boolean = true, model: GamesRummyMatchModel? = null): @Composable () -> Unit {
        val (_, rummy) = rig(state)
        return W4cDesktopSnapshots.frame(dark, w, h) {
            if (model != null) {
                GamesRummyMatchView(rummy, USER, ME, reduceMotion, onRules = {}, onBack = {}, now = { NOW }, modifier = Modifier.fillMaxSize(), model = model)
            } else {
                GamesRummyMatchView(rummy, USER, ME, reduceMotion, onRules = {}, onBack = {}, now = { NOW }, modifier = Modifier.fillMaxSize())
            }
        }
    }
}

class GamesRummyMatchSnapshotDesktopTest {
    private val scene = GamesRummyMatchScene

    /** 음성 기준선 = 받침대 한 장이 다르다 — 비교가 내용을 본다. */
    private fun baseline(dark: Boolean) = scene.frame(dark, scene.state(rack = """["A5","A6","A7","A8","A9","A10","A11","A12","A13","B1","B2","B3","B4","B5","B6","B8","C1","C2","C3","D10","D11","D12","D13"]"""))

    @Test
    fun matchLandscapeLight() = W4cDesktopSnapshots.check("rummy", "match-landscape-light", scene.W, scene.H, scene.frame(false), baseline(false))

    @Test
    fun matchLandscapeDark() = W4cDesktopSnapshots.check("rummy", "match-landscape-dark", scene.W, scene.H, scene.frame(true), baseline(true))
}
