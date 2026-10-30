// 원본: Tests/checkTests/V0360TetrisDuelStoreTests.swift 「한 판 한 기기」 절(V0369TetrisOneWriterStoreTests ①~⑥ · 와이어) ·
//       Tests/CheckMobileKitTests/GamesTetrisDuelWiringTests.swift §9 · GamesTetrisDuelMatchTests.swift(다른 기기 카드 표) @ 75c31cd2
//
// 2026-10-30 '꼭대기 안 찼는데 졌다' 두 판: 같은 계정의 맥 두 대가 초인종을 함께 받고 둘 다 판을 세웠다. 입력 없는 쪽의 판이
// 1초마다 같은 서버 행을 덮어쓰고, 그 판의 탑아웃이 진짜 판을 대신 닫았다. 이 파일은 **두 스토어(같은 사람 · 다른 기기)** 를
// 한 흉내 서버 위에 세우고, 판을 두는 기기가 하나뿐인지를 **보고 건수 · 판 루프 · 창 띄우기 횟수**로 잰다.
// 서버 쪽 규칙(other_device · my_device)의 실서버 왕복은 마이그레이션 프로브가 잰다 — 여기 흉내 서버는 그 응답 모양만 낸다.
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.MemoryPrefs
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TetrisOneWriterStoreTest {
    private companion object {
        const val MATCH = "m-1"
        const val NOW_MS: Long = 1_789_621_500_000
        val ME = StoreFixtures.USER
        val PEER = StoreFixtures.PEER
    }

    /**
     * 공유 흉내 서버(Swift `TDServer` 의 한 판 한 기기 몫). [writer] = 내 자리를 연 기기 이름(null = 기록 없음 → my_device null · 잠금 없음).
     * [knowsDevices] 가 false 면 **옛 서버**다: my_device 를 안 싣고 기기를 가르지 않는다(누가 보고해도 쓴다).
     */
    private class Server {
        var status = "active"
        var writer: String? = null
        var knowsDevices = true
        var meReady = false
        var meSeq = 0
        var opponentReady = true
        var startAtMs: Long? = null
        var winner: String? = null
        var endReason: String? = null
        val reportsByDevice = mutableMapOf<String, Int>()

        fun myDevice(device: String): String? = when {
            !knowsDevices -> null
            writer == null -> null
            writer == device -> "this"
            else -> "other"
        }

        fun state(myDevice: String?): String =
            """{"match_id":"$MATCH","status":"$status","stake":3,"seed":4242,"server_now_ms":$NOW_MS,"accepted_at_ms":${NOW_MS - 2_000},""" +
                (startAtMs?.let { """"start_at_ms":$it,"max_end_ms":${it + 480_000},""" } ?: "") +
                """"ready_deadline_ms":${NOW_MS + 28_000},""" +
                (if (status == "finished") """"finished_at_ms":$NOW_MS,"result":"${if (winner == ME) "opponent_win" else "challenger_win"}",""" else "") +
                (winner?.let { """"winner":"$it",""" } ?: "") + (endReason?.let { """"end_reason":"$it",""" } ?: "") +
                """"me":{"id":"$ME","display_name":"나","ready":$meReady,"seq":$meSeq},""" +
                """"opponent":{"id":"$PEER","display_name":"라이벌","ready":$opponentReady,"seq":0},"ruby_balance":97""" +
                (myDevice?.let { ""","my_device":"$it"""" } ?: "") + "}"

        fun envelope(status: String, device: String): Reply =
            Reply.Json("""{"status":"$status","state":${state(myDevice(device))},"server_now_ms":$NOW_MS}""")

        fun lobby(): Reply = Reply.Json(
            """{"status":"ok","server_now_ms":$NOW_MS,"me":{"ruby_balance":97,"wins":0,"losses":0,"draws":0""" +
                (if (status == "active") ""","active_match_id":"$MATCH"""" else "") +
                ""","incoming":[]},"users":[],"matches":[]}""",
        )

        /** 그 기기의 신청(내가 신청자) — 신청한 기기가 자리를 연다. */
        fun challenge(device: String): Reply {
            status = "pending"
            writer = if (knowsDevices) device else null
            return Reply.Json("""{"status":"ok","match_id":"$MATCH","expires_at_ms":${NOW_MS + 60_000},"server_now_ms":$NOW_MS}""")
        }

        /** 그 기기의 수락(내가 받는 사람) — 수락한 기기가 자리를 연다. 응답 상태는 그 기기 시점이다. */
        fun accept(device: String): Reply {
            status = "active"
            writer = if (knowsDevices) device else null
            return Reply.Json("""{"status":"ok","accepted":true,"state":${state(myDevice(device))},"server_now_ms":$NOW_MS}""")
        }

        /** 그 기기의 기권 — 자리를 연 기기가 따로 있으면 정산 없이 other_device. */
        fun resign(device: String): Reply {
            if (knowsDevices && writer != null && writer != device) return envelope("other_device", device)
            status = "finished"
            winner = PEER
            endReason = "resign"
            return envelope("ok", device)
        }

        /** 서버 쓰기 규칙 흉내: 자리를 연 기기가 따로 있으면 **아무것도 안 쓰고** other_device. */
        fun report(body: String, device: String): Reply {
            reportsByDevice[device] = (reportsByDevice[device] ?: 0) + 1
            if (knowsDevices && writer != null && writer != device) return envelope("other_device", device)
            if (status != "active") return envelope("stale", device)
            if (!meReady) {
                meReady = true
                if (opponentReady && startAtMs == null) startAtMs = NOW_MS + 3_000
            }
            val seq = Regex("\"p_seq\":(\\d+)").find(body)?.groupValues?.get(1)?.toInt() ?: 0
            if (seq <= meSeq) return envelope("stale", device)
            meSeq = seq
            return envelope("ok", device)
        }

        fun route(device: String): (RecordedRequest) -> Reply? = { r ->
            when (r.rpcName) {
                "tetris_lobby" -> lobby()
                "tetris_state" -> envelope("ok", device)
                "tetris_report" -> report(r.bodyText, device)
                "tetris_respond" -> accept(device)
                "tetris_challenge" -> challenge(device)
                "tetris_resign" -> resign(device)
                "tetris_ranking" -> Reply.Json("""{"status":"ok","rows":[]}""")
                else -> null
            }
        }
    }

    /** 같은 사람(`ME`)의 **기기 하나** — 자기 스텁 하네스 · 창·주의·말풍선 세기. */
    private class Device(val harness: StoreHarness) {
        val tetris: TetrisDuelStore get() = harness.tetris
        var presents = 0
        var attentionRequests = 0
        val attentions = mutableListOf<TetrisDuelAttention>()
        fun reports(): Int = harness.server.count("tetris_report")
    }

    private suspend fun TestScope.device(server: Server, name: String, defaults: MemoryPrefs? = null): Device {
        val h = StoreHarness(this, AppConfig(duelsEnabled = true), route = server.route(name))
        h.signIn()
        runCurrent()
        val d = Device(h)
        h.tetris.uptime = { testScheduler.currentTime / 1000.0 }
        h.tetris.defaults = defaults
        h.tetris.presentWindow = { d.presents += 1 }
        h.tetris.requestAttention = { d.attentionRequests += 1 }
        h.tetris.onAttention = { d.attentions += it }
        return d
    }

    /** 초인종 한 번이 끝까지 돈다(로비 → 진행 중 판 상태). */
    private fun TestScope.ring(d: Device) {
        d.tetris.handleSignal()
        runCurrent()
    }

    private fun TestScope.step(vararg devices: Device) {
        advanceTimeBy(1_000)
        for (d in devices) {
            d.tetris.tick()
            runCurrent()
        }
    }

    /** 받는 사람 쪽 두 기기: A 가 수락하고, B 는 초인종·상태만 받는다. [knowsDevices] = 새 서버(my_device) / 옛 서버(기록으로 가른다). */
    private suspend fun TestScope.acceptOnTwoDevices(knowsDevices: Boolean) {
        val server = Server().apply { this.knowsDevices = knowsDevices; status = "pending"; opponentReady = false }
        val a = device(server, "A")
        val b = device(server, "B")

        a.tetris.respond(MATCH, accept = true)
        runCurrent()
        assertTrue(a.tetris.match?.id == MATCH && a.tetris.duel != null && a.tetris.gameLoopJob != null, "수락한 A 가 판을 안 세웠다")
        assertEquals(1, a.presents, "수락한 A 가 창을 안 띄웠다 — 준비가 안 나가 no_show 로 접힌다")
        assertTrue(a.tetris.ownsMatch(MATCH) && !a.tetris.playingElsewhere)

        // B: 서버는 사람의 **모든 기기**에 초인종을 울린다(둘째 준비 · 공격 · 정산).
        ring(b)
        assertEquals(MATCH, b.tetris.match?.id, "전제: B 도 진행 중 판을 안다(초인종 → 로비 → 상태)")
        assertTrue(b.tetris.duel == null && b.tetris.gameLoopJob == null, "B 가 판을 세웠다 — 입력 없는 판이 1초마다 보고한다")
        assertTrue(b.presents == 0 && b.attentionRequests == 0 && b.attentions.isEmpty(), "B 가 창·주의를 불렀다")
        assertTrue(b.tetris.playingElsewhere)
        assertEquals(TetrisDuelNoticeText.otherDevice, b.tetris.notice)
        assertEquals(TetrisDuelPhase.ready, b.tetris.phase)
        assertFalse(b.tetris.ownsMatch(MATCH))

        // A 가 둔다: 창 → 준비 → (상대 준비) → 시작 → 하트비트. 그동안 B 는 창을 열고 틱·초인종을 받아도 보고 0.
        a.tetris.windowDidShow()
        runCurrent()
        server.opponentReady = true
        server.startAtMs = NOW_MS + 3_000
        b.tetris.windowDidShow()
        runCurrent()
        repeat(6) { step(a, b) }
        ring(b)
        assertEquals(TetrisDuelPhase.playing, a.tetris.phase, "A 의 판이 안 흘렀다")
        assertTrue((server.reportsByDevice["A"] ?: 0) >= 5, "A 의 보고가 ${server.reportsByDevice["A"] ?: 0}건뿐이다")
        assertNull(server.reportsByDevice["B"], "B 가 보고를 냈다")
        assertEquals(0, b.reports(), "B 가 보고를 ${b.reports()}건 냈다")
        assertTrue(b.tetris.duel == null && b.tetris.gameLoopJob == null && b.presents == 0)
        assertTrue(server.meReady && server.meSeq == a.tetris.duel?.seq, "서버 행이 A 의 판이 아니다")
        a.tetris.reset()
        b.tetris.reset()
    }

    /** ① 받는 쪽 두 기기(새 서버 my_device): 수락한 A 만 판을 두고, 초인종·상태만 받은 B 는 판 루프·보고·창이 0 이다. */
    @Test
    fun onlyTheAcceptingDevicePlaysOnTheNewServer() = runTest {
        // 없으면(0.3.60~0.3.68): B 도 판을 세워 입력 없이 1초마다 보고하고 그 판의 탑아웃이 A 의 판을 닫는다(2026-10-30 두 판).
        acceptOnTwoDevices(knowsDevices = true)
    }

    /** ③ 받는 쪽 두 기기(옛 서버 — my_device 없음): '이 기기가 연 판' 기록이 가른다 — 수락한 A 만 두고 B 는 아무것도 안 한다. */
    @Test
    fun onlyTheAcceptingDevicePlaysOnAnOldServer() = runTest {
        // 없으면: 서버 마이그레이션 전(또는 되돌린 뒤) 창에서 클라 마개가 통째로 빠진다 — my_device 만 믿으면 null 이 '둔다' 로 읽힌다.
        acceptOnTwoDevices(knowsDevices = false)
    }

    /** ② 신청 쪽 두 기기: 수락 초인종이 둘 다에 가도 창·준비·보고는 신청을 보낸 A 뿐이다(새 서버 · 옛 서버). */
    @Test
    fun onlyTheChallengingDevicePlays() = runTest {
        // 없으면: 수락 초인종을 받은 신청자의 모든 기기가 창을 띄우고, 보이는 창은 곧바로 준비를 낸다 — 입력 없는 기기가
        // 진짜 판을 덮거나 그 판의 탑아웃으로 대결을 닫는다.
        for (knowsDevices in listOf(true, false)) {
            val server = Server().apply { this.knowsDevices = knowsDevices; opponentReady = false }
            val a = device(server, "A")
            val b = device(server, "B")
            // 둘 다 창이 열려 있다(최악 — 보이는 창은 판이 서는 순간 준비를 낸다).
            a.tetris.isWindowVisible = true
            b.tetris.isWindowVisible = true
            a.tetris.challenge(PEER, TetrisDuelStake.three)
            runCurrent()
            assertTrue(a.tetris.outgoing?.id == MATCH && a.tetris.ownsMatch(MATCH), "knowsDevices=$knowsDevices")
            assertFalse(b.tetris.ownsMatch(MATCH))

            server.status = "active"           // 상대가 수락했다 — 신청자의 모든 기기에 초인종
            ring(a)
            ring(b)
            assertTrue(a.tetris.duel != null && a.tetris.gameLoopJob != null && a.presents == 1, "신청한 A 가 판·창을 안 세웠다 knowsDevices=$knowsDevices")
            assertEquals(MATCH, b.tetris.match?.id, "전제: B 도 판을 안다")
            assertTrue(b.tetris.duel == null && b.tetris.gameLoopJob == null, "B 가 판을 세웠다 knowsDevices=$knowsDevices")
            assertTrue(b.presents == 0 && b.attentionRequests == 0 && b.attentions.isEmpty(), "B 가 창을 띄웠다")
            assertTrue(b.tetris.playingElsewhere)
            assertEquals(TetrisDuelNoticeText.otherDevice, b.tetris.notice)

            // 보이는 창의 준비는 곧바로 — A 만. 상대 준비 뒤 하트비트도 A 만.
            a.tetris.tick()
            runCurrent()
            b.tetris.tick()
            runCurrent()
            assertEquals(1, server.reportsByDevice["A"], "신청한 A 가 준비를 안 냈다")
            assertTrue(server.meReady)
            server.opponentReady = true
            server.startAtMs = NOW_MS + 3_000
            repeat(5) { step(a, b) }
            assertEquals(TetrisDuelPhase.playing, a.tetris.phase)
            assertTrue((server.reportsByDevice["A"] ?: 0) >= 5)
            assertNull(server.reportsByDevice["B"], "B 가 보고를 냈다 knowsDevices=$knowsDevices")
            assertEquals(0, b.reports())
            a.tetris.reset()
            b.tetris.reset()
        }
    }

    /** ④ 보고·기권이 other_device 로 돌아오면 곧바로 물러난다 — 판 루프·구동기·기록이 내려가고 안내 한 줄 · 그 뒤 보고 0. */
    @Test
    fun anOtherDeviceReplyStopsTheLoop() = runTest {
        // 없으면: 서버가 거절한 보고를 '보고 거절' 로그만 남기고 1초마다 계속 낸다(옛 코어의 unknown 갈래) — 판은 흐르는데
        // 서버에는 한 줄도 안 닿아 사용자는 화면의 판으로 15초 침묵 패를 한다.
        val server = Server().apply { writer = "A" }
        val a = device(server, "A")
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        a.tetris.windowDidShow()
        runCurrent()
        advanceTimeBy(3_500)
        a.tetris.tick()
        runCurrent()
        assertTrue(a.tetris.phase == TetrisDuelPhase.playing && a.tetris.gameLoopJob != null && a.tetris.ownsMatch(MATCH))

        // 같은 계정이 이 판을 다른 기기 세션으로 잡았다(예: 판 중 다시 로그인) — 서버가 A 의 다음 보고를 돌려보낸다.
        server.writer = "Z"
        val before = server.reportsByDevice["A"] ?: 0
        step(a)
        assertEquals(before + 1, server.reportsByDevice["A"])
        assertTrue(a.tetris.duel == null && a.tetris.gameLoopJob == null, "other_device 뒤에도 판 루프·구동기가 남았다")
        assertEquals(TetrisDuelNoticeText.otherDevice, a.tetris.notice)
        assertTrue(a.tetris.playingElsewhere)
        assertTrue(!a.tetris.ownsMatch(MATCH) && MATCH in a.tetris.yieldedMatchIDs)
        assertEquals(TetrisDuelPhase.ready, a.tetris.phase)
        assertEquals(false, a.tetris.match?.isFinished, "물러났는데 판 상태까지 지웠다(안내를 그릴 자리가 없다)")

        // 그 뒤로는 보고가 한 건도 안 나간다(틱 · 창 · 초인종 모두).
        repeat(5) { step(a) }
        a.tetris.windowDidShow()
        runCurrent()
        ring(a)
        assertEquals(before + 1, server.reportsByDevice["A"], "물러난 판에 보고를 또 냈다")
        // ★ 물러난 판은 서버가 다시 'this' 라 해도 두지 않는다(같은 세션을 쓰는 두 프로세스가 번갈아 자리를 뺏지 않게).
        server.writer = "A"
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(a.tetris.duel == null && a.tetris.playingElsewhere)

        // 기권도 같은 문 — 서버가 정산하지 않았다. 결과 없이 안내 한 줄.
        server.writer = "Z"
        a.tetris.resign()
        runCurrent()
        assertEquals(1, a.harness.server.count("tetris_resign"))
        assertEquals(false, a.tetris.match?.isFinished)
        assertEquals(TetrisDuelNoticeText.otherDevice, a.tetris.notice)
        assertEquals(TetrisDuelNoticeText.otherDevice, TetrisDuelNoticeText.resign(TetrisRPCStatus.otherDevice))
        a.tetris.reset()
        assertTrue(a.tetris.yieldedMatchIDs.isEmpty() && !a.tetris.playingElsewhere)
    }

    /**
     * ④-b 기권이 **먼저** other_device 로 돌아와도 물러난다(보고 거절을 거치지 않은 길) — 그 뒤 서버가 다시 'this' 라 해도 두지 않는다.
     * Kotlin 이식에서 더한 시험: ④ 는 보고 거절이 먼저 물러나게 해서 기권 갈래의 물러남이 빠져도 초록이었다(돌연변이 확인).
     */
    @Test
    fun aResignRefusedByAnotherDeviceAlsoYields() = runTest {
        // 없으면: 판을 두던 기기가 기권을 눌렀는데 서버가 다른 기기의 판이라 돌려보내도 그 판을 '이 기기 판'으로 들고 있다가,
        // 같은 세션 두 프로세스가 번갈아 자리를 잡는 맥에서 다시 판을 세우고 보고를 낸다.
        val server = Server().apply { writer = "A" }
        val a = device(server, "A")
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(a.tetris.duel != null && a.tetris.ownsMatch(MATCH))

        server.writer = "Z"
        a.tetris.resign()
        runCurrent()
        assertTrue(MATCH in a.tetris.yieldedMatchIDs, "기권 거절이 그 판에서 물러나지 않았다")
        assertTrue(a.tetris.duel == null && a.tetris.playingElsewhere && !a.tetris.ownsMatch(MATCH))
        assertEquals(TetrisDuelNoticeText.otherDevice, a.tetris.notice)
        assertEquals(0, server.reportsByDevice["A"] ?: 0, "전제: 보고 거절을 거치지 않았다")

        server.writer = "A"
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(a.tetris.duel == null && a.tetris.gameLoopJob == null && a.tetris.playingElsewhere, "물러난 판을 다시 세웠다")
        a.tetris.reset()
    }

    /** ⑤ '이 기기가 연 판' 기록은 앱을 다시 켜도 산다(defaults) — 옛 서버에서도 다시 켠 A 가 자기 판을 둔다 · 끝나면 걷힌다 · 한 시간 뒤 안 쓴다. */
    @Test
    fun ownershipSurvivesARestart() = runTest {
        // 없으면: 판 중에 앱을 다시 켠 기기가 옛 서버(my_device 없음)에서 자기 판을 못 알아봐 보고를 멈추고 15초 침묵 패를 한다.
        val shared = MemoryPrefs()
        val fresh = MemoryPrefs()
        val key = TetrisDuelStore.ownedMatchesKey(ME)
        val server = Server().apply { knowsDevices = false; status = "pending" }
        val first = device(server, "A", shared)
        first.tetris.respond(MATCH, accept = true)
        runCurrent()
        assertTrue(first.tetris.duel != null && first.tetris.ownsMatch(MATCH))
        assertTrue(shared.getString(key)?.contains("\"$MATCH\"") == true, "수락 기록이 defaults 에 안 남았다")

        // 앱을 껐다 켰다 — 새 프로세스의 새 스토어가 **같은 defaults** 로 선다.
        val again = device(server, "A", shared)
        assertTrue(again.tetris.ownsMatch(MATCH))
        again.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(again.tetris.duel != null && again.tetris.gameLoopJob != null && !again.tetris.playingElsewhere, "다시 켠 A 가 자기 판을 못 알아봤다")
        // ★ 기준선: 기록이 없는 defaults 로 선 스토어(같은 사람 · 같은 옛 서버 응답)는 안 둔다.
        val stranger = device(server, "B", fresh)
        stranger.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(stranger.tetris.match?.id == MATCH && stranger.tetris.duel == null && stranger.tetris.playingElsewhere)

        // 끝나면 기록이 걷힌다(쌓이지 않는다).
        server.status = "finished"
        server.winner = ME
        server.endReason = "topout"
        again.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(again.tetris.match?.isFinished == true && !again.tetris.playingElsewhere)
        assertFalse(again.tetris.ownsMatch(MATCH))
        assertNull(shared.getString(key), "끝난 판의 기록이 남았다")

        // 유효 기간: 한 시간 지난 기록으로는 두지 않는다.
        val other = "7e7e0000-0000-4000-8000-0000000000aa"
        again.tetris.noteOwnsMatch(other)
        assertTrue(again.tetris.ownsMatch(other))
        val wall = again.tetris.clock().timeIntervalSince1970
        again.tetris.clock = { SwiftDate(wall + TetrisDuelStore.ownedMatchTTLSeconds + 1) }
        assertFalse(again.tetris.ownsMatch(other), "한 시간 지난 기록으로 판을 뒀다")
        first.tetris.reset()
        again.tetris.reset()
        stranger.tetris.reset()
    }

    /** ⑥ 기록이 없어도 서버가 my_device 'this' 라 하면 둔다(재설치·기록 유실) · 기록이 있어도 'other' 면 안 둔다 — 서버 말이 앞선다. */
    @Test
    fun theServerSaysThisDevice() = runTest {
        // 없으면: 앱을 지웠다 깐 기기(기록 없음)가 자기가 연 판을 못 두고 침묵 패를 하거나, 서버가 막은 기기가 기록만 믿고 판을 세운다.
        val server = Server().apply { writer = "A" }
        val a = device(server, "A")
        assertFalse(a.tetris.ownsMatch(MATCH))
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(a.tetris.duel != null && a.tetris.gameLoopJob != null && !a.tetris.playingElsewhere)
        assertEquals(1, a.presents, "서버가 이 기기라 했는데 창을 안 띄웠다")
        assertTrue(a.tetris.ownsMatch(MATCH), "서버 말로 기록을 맞추지 않았다")
        a.tetris.windowDidShow()
        runCurrent()
        assertEquals(1, server.reportsByDevice["A"])

        // ★ 기준선: 같은 판에 기록이 있다고 믿는 B 라도 서버가 'other' 라 하면 안 둔다(기록도 지운다).
        val b = device(server, "B")
        b.tetris.noteOwnsMatch(MATCH)
        assertTrue(b.tetris.ownsMatch(MATCH))
        b.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(b.tetris.duel == null && b.tetris.playingElsewhere && !b.tetris.ownsMatch(MATCH) && b.presents == 0)
        assertNull(server.reportsByDevice["B"])
        a.tetris.reset()
        b.tetris.reset()
    }

    /** 와이어: other_device 는 자기 status 로 읽고 state 를 싣는다 · my_device 는 this/other/없음(null). */
    @Test
    fun wireReadsOtherDeviceAndMyDevice() {
        // 없으면: other_device 가 unknown 으로 접혀 '보고 거절' 로그만 남고 판 루프가 돈다(옛 코어의 바로 그 갈래).
        val server = Server().apply { writer = "Z" }
        val refused = SwiftJson.decode(TetrisActionResponse.serializer(), (server.envelope("other_device", "A") as Reply.Json).body)
        assertEquals(TetrisRPCStatus.otherDevice, refused.status)
        assertEquals("other", refused.state?.myDevice)
        assertEquals(MATCH, refused.state?.matchId)
        assertEquals("this", SwiftJson.decode(TetrisStatePayload.serializer(), server.state("this")).myDevice)
        assertNull(SwiftJson.decode(TetrisStatePayload.serializer(), server.state(null)).myDevice)
        val nullDevice = server.state(null).removeSuffix("}") + ""","my_device":null}"""
        assertNull(SwiftJson.decode(TetrisStatePayload.serializer(), nullDevice).myDevice)
    }

    /**
     * 다른 기기가 두는 판을 폰에서 열면 기다림 대신 그 사실 · '나가면 져요' 없음 · 화면 꺼짐 방지 없음 — 같은 판에 this 면 셋 다 선다
     * (Swift GamesTetrisDuelWiringTests §9 둘째 · GamesTetrisDuelMatchTests 의 끝난 판 표).
     */
    @Test
    fun aMatchPlayedOnAnotherDeviceShowsTheFactNotTheWaitingCard() = runTest {
        // 없으면: 판을 두지 않는 폰이 ready 에 머물러 "상대를 기다리는 중 · 앱을 켜 둔 채 기다려 주세요" 카드와
        // "판 중에 앱을 나가면 져요" 를 띄우고(둘 다 이 폰에는 거짓이다), 남의 기기 판이 끝날 때까지 최대 8분 화면을 켜 둔다.
        fun chrome(t: TetrisDuelStore) = GamesTetrisDuelChrome(
            assertNotNull(t.match), t.phase, t.myStats, t.notice, t.connectionTrouble, playingElsewhere = t.playingElsewhere,
        )
        val server = Server().apply { writer = "Z" }
        val b = device(server, "B")
        val games = GamesStore(b.harness.context).also { it.appDidBecomeActive() }
        b.tetris.refreshMatch(MATCH)
        runCurrent()
        assertTrue(b.tetris.phase == TetrisDuelPhase.ready && b.tetris.playingElsewhere)
        val elsewhere = chrome(b.tetris)
        assertTrue(elsewhere.stage == GamesTetrisDuelChrome.Stage.waiting && elsewhere.playingElsewhere, "덮개가 기다림 갈래를 탄다")
        assertFalse(elsewhere.showsLeaveWarning, "판을 두지 않는 폰에 '판 중에 앱을 나가면 져요' 가 선다")
        assertFalse(elsewhere.acceptsInput)
        assertNull(elsewhere.notice, "덮개 제목과 같은 안내가 판 밑에 한 번 더 선다")
        assertFalse(games.wantsIdleTimerDisabled, "남의 기기 판인데 이 폰 화면을 켜 둔다")
        b.tetris.reset()

        // ★ 기준선: 같은 판에 서버가 'this' 라 하면 기다림 카드 · 경고 · 화면 꺼짐 방지가 그대로 선다.
        val mineServer = Server().apply { writer = "A" }
        val a = device(mineServer, "A")
        val mineGames = GamesStore(a.harness.context).also { it.appDidBecomeActive() }
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        val playing = chrome(a.tetris)
        assertTrue(playing.stage == GamesTetrisDuelChrome.Stage.waiting && !playing.playingElsewhere)
        assertTrue(playing.showsLeaveWarning, "기준선이 안 갈린다 — 이 폰의 판에서도 경고가 사라졌다")
        assertTrue(mineGames.wantsIdleTimerDisabled, "기준선이 안 갈린다 — 이 폰의 판에서도 화면이 꺼질 수 있다")

        // 표 쪽: 끝난 판에서는 '다른 기기' 가 아니다(결과 카드가 말한다) · 끝난 판의 안내 줄은 지우지 않는다.
        mineServer.status = "finished"
        mineServer.winner = PEER
        mineServer.endReason = "topout"
        a.tetris.refreshMatch(MATCH)
        runCurrent()
        val closed = GamesTetrisDuelChrome(
            assertNotNull(a.tetris.match), a.tetris.phase, null, TetrisDuelNoticeText.otherDevice, false, playingElsewhere = true,
        )
        assertTrue(closed.stage == GamesTetrisDuelChrome.Stage.finished && !closed.playingElsewhere && closed.result != null)
        assertEquals(TetrisDuelNoticeText.otherDevice, closed.notice, "끝난 판의 안내 줄을 표가 지웠다")
        a.tetris.reset()
    }
}
