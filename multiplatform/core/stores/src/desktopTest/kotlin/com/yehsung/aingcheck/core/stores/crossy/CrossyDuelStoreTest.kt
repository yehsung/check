// 원본: Tests/checkTests/V03xxCrossyDuelStoreTests.swift · V03xxCrossyDuelGhostTests.swift · V03xxCrossyDuelFramesTests.swift @ e4995a3a(뽑아 옮김) — Android 판 8
//
// 1:1 길건너 스토어 · 프레임 장부 계약. **모양이 아니라 결과를 잰다.** 서버 응답 모양은 하네스 픽스처 원문(Tests/checkTests/Fixtures/crossy-duel-rpc —
// 맥 시험과 같은 파일)을 그대로 넣는다. 단언마다 결함 변이에서 갈리는 기준선 짝을 둔다.
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.CrossyDuelLockNotAvailable
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.StubReply
import com.yehsung.aingcheck.core.stores.gomoku.decodeFixture
import com.yehsung.aingcheck.core.stores.gomoku.fixtureText
import com.yehsung.aingcheck.core.stores.gomoku.settle
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.CrossyDuelActionResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelFramesRow
import com.yehsung.aingcheck.core.wire.games.CrossyDuelLobbyResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelSideRow
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val FIX = "Tests/checkTests/Fixtures/crossy-duel-rpc"
private const val ME_A = "06294292-2330-4534-a668-2492b7976017"
private const val ME_B = "73b739c3-b64d-4d30-9068-b358f413d542"
private const val ME_C = "cc967f15-daa3-4f82-9285-5cd422a78aa0"
private const val ME_D = "dfa8b1d4-02df-44ef-b40d-3d1d86f14fd1"

private fun action(name: String): CrossyDuelActionResponse = decodeFixture(FIX, name, CrossyDuelActionResponse.serializer())
private fun lobby(name: String): CrossyDuelLobbyResponse = decodeFixture(FIX, name, CrossyDuelLobbyResponse.serializer())

/** 프레임 소켓 스텁 — 시킨 일만 적는다. */
private class StubFrameChannel : CrossyDuelFrameChannel {
    override var onEvent: ((CrossyDuelFrameChannelEvent) -> Unit)? = null
    val connects = mutableListOf<String>()
    val sent = mutableListOf<JsonObject>()
    var disconnects = 0
    override fun connect(projectURL: String, apiKey: String, accessToken: String, topic: String) { connects += topic }
    override fun send(event: String, payload: JsonObject) { sent += payload }
    override fun pushAccessToken(token: String) {}
    override fun disconnect() { disconnects += 1 }
}

@OptIn(ExperimentalCoroutinesApi::class)
class CrossyDuelStoreTest {
    private class Rig(val store: CrossyDuelStore, val server: DuelStubServer, val host: FakeDuelHost) {
        var up: Double = 1_000.0
    }

    /** 벽시계는 픽스처 `server_now_ms` 근처(차이는 서버 시계 보정이 흡수한다). 판 루프 · 폴링은 크게 재운다. */
    private fun TestScope.rig(me: String, duels: Boolean = true, nowMs: Double = 1_793_979_182_538.0): Rig {
        val server = DuelStubServer(this)
        val clock = { SwiftDate(nowMs / 1000) }
        val host = FakeDuelHost(server.service(clock), me, AppConfig(duelsEnabled = duels), clock)
        val store = CrossyDuelStore(host, storeScope(), clock)
        store.gameLoopStepSeconds = 3_600.0
        store.pollStepSeconds = 3_600.0
        val rig = Rig(store, server, host)
        store.uptime = { rig.up }
        return rig
    }

    // MARK: 픽스처 — 끝난 판(판정은 서버 값만)

    @Test
    fun finishedFixturesKeepServerVerdict() = runTest {
        // 내 기준 결과 · 사유 · 루비 · 굳힌 점수가 서버 값 그대로다. 기준선: 같은 판을 상대 눈으로 읽으면 결과가 뒤집힌다.
        val loss = rig(ME_A)
        loss.store.applyState(action("crossy_duel_state__finished_goal_loss").state!!)
        val m = loss.store.match!!
        assertEquals(CrossyDuelOutcome.loss, m.outcome)
        assertEquals(CrossyDuelEndReason.goal, m.endReason)
        assertEquals(-5, m.rubyDelta)
        assertEquals(37, m.finalMyScore)
        assertEquals(100, m.finalOpponentScore)
        assertEquals(CrossyDuelPhase.finished, loss.store.phase)

        val win = rig(ME_C)
        win.store.applyState(action("crossy_duel_state__finished_resign_win").state!!)
        assertEquals(CrossyDuelOutcome.win, win.store.match!!.outcome)
        assertEquals(com.yehsung.aingcheck.core.rules.duel.DuelFee.winnerNet(5), win.store.match!!.rubyDelta)
        assertEquals("상대가 기권했어요", CrossyDuelNoticeText.endReason(win.store.match!!.endReason, win.store.match!!.outcome))

        val draw = rig(ME_C)
        draw.store.applyState(action("crossy_duel_state__finished_time_cap_draw").state!!)
        assertEquals(CrossyDuelOutcome.draw, draw.store.match!!.outcome)
        assertEquals(0, draw.store.match!!.rubyDelta)

        val noShow = rig(ME_D)
        noShow.store.applyState(action("crossy_duel_state__finished_no_show").state!!)
        val ns = noShow.store.match!!
        assertEquals(CrossyDuelEndReason.noShow, ns.endReason)
        assertEquals("준비하지 않아 판이 열리지 않았어요 · 판돈은 돌려받았어요", CrossyDuelNoticeText.endReason(ns.endReason, ns.outcome, ns.meReady, ns.opponentReady))
    }

    @Test
    fun finishedGoalLossShowsLocalScoreWhenHigher() = runTest {
        // Q3 (가): goal 로 진 판만 max(final.me, 로컬). 기준선: 3분 끝(time_cap)은 final 그대로.
        val r = rig(ME_A)
        r.store.applyState(action("crossy_duel_state__finished_goal_loss").state!!)
        assertEquals(41, finishedMyScore(r.store.match!!, 41))
        assertEquals(37, finishedMyScore(r.store.match!!.copy(endReason = CrossyDuelEndReason.timeCap), 41))
    }

    // MARK: 진행 판 · 한 판 한 기기 · 프레임

    @Test
    fun playingFixtureBuildsDuelAndOpensFrames() = runTest {
        // 이 기기가 두는 판(my_device this · frames 켬) → 구동기 · 장부가 서고 그 토픽으로 연다. 기준선: 다른 기기 판(my_device other)은 두지 않는다.
        val r = rig(ME_B)
        val channel = StubFrameChannel()
        r.store.makeFrameChannel = { channel }
        r.store.applyState(action("crossy_duel_state__playing").state!!, r.up)
        assertNotNull(r.store.duel)
        assertFalse(r.store.playingElsewhere)
        assertNotNull(r.store.frameLink)
        assertEquals(listOf("crossy_duel:2c541e9b-9a7e-4d45-8513-076d5752bf2a"), channel.connects)
        r.store.reset()
        assertEquals(1, channel.disconnects, "로그아웃은 열린 프레임 소켓을 닫는다")

        val other = rig(ME_A)
        val otherChannel = StubFrameChannel()
        other.store.makeFrameChannel = { otherChannel }
        other.store.applyState(action("crossy_duel_state__other_device").state!!, other.up)
        assertNull(other.store.duel)
        assertTrue(other.store.playingElsewhere)
        assertEquals(CrossyDuelNoticeText.otherDevice, other.store.notice)
        assertTrue(otherChannel.connects.isEmpty())
    }

    @Test
    fun firstReportCarriesNextSeqAndReadyGateUsesServerReady() = runTest {
        // 시작한 판(서버가 준비를 이미 받았다 — me.ready) → 창이 안 보여도 첫 보고가 나간다(seq = 서버 seq + 1).
        val r = rig(ME_B)
        r.server.queue("crossy_duel_report", StubReply.Json(fixtureText(FIX, "crossy_duel_report__playing")))
        r.store.applyState(action("crossy_duel_state__playing").state!!, r.up)
        assertEquals(CrossyDuelPhase.playing, r.store.phase, "시작 뒤 보고가 서버에 있으면(재개) 곧바로 달리기다")
        r.up += 0.5
        r.store.tick()
        settle()
        assertNotNull(r.store.duel?.lastSent, "보낸 보고가 장부에 적혔다")
        assertEquals(1, r.server.count("crossy_duel_report"))
        val body = r.server.lastBody("crossy_duel_report")
        assertEquals(2L, (body["p_seq"] as JsonPrimitive).longOrNull)
    }

    @Test
    fun otherDeviceReportYields() = runTest {
        // 보고가 other_device 로 돌아오면 곧바로 물러난다(구동기를 버리고 안내 한 줄). 기준선: ok 보고는 판을 그대로 둔다.
        val r = rig(ME_A)
        r.store.applyState(action("crossy_duel_state__playing").state!!.copy(myDevice = "this", me = action("crossy_duel_state__playing").state!!.opponent, opponent = action("crossy_duel_state__playing").state!!.me), r.up)
        assertNotNull(r.store.duel)
        val id = r.store.match!!.id
        r.store.applyReportResult(DuelCall.Success(action("crossy_duel_report__other_device")), id, r.up)
        assertNull(r.store.duel)
        assertTrue(r.store.playingElsewhere)
        assertTrue(id in r.store.yieldedMatchIDs)
    }

    @Test
    fun lockTimeoutIsNotAFailure() = runTest {
        // 55P03 두 번 → 연결 확인 중 안 켜짐(실패로 안 셈). 기준선: 보통 실패 두 번 → 켜짐.
        val r = rig(ME_B)
        r.store.applyState(action("crossy_duel_state__playing").state!!, r.up)
        val id = r.store.match!!.id
        repeat(2) { r.store.applyReportResult(DuelCall.Failure(CrossyDuelLockNotAvailable()), id, r.up, CrossyDuelSessionKind.goal) }
        assertFalse(r.store.connectionTrouble)
        repeat(2) { r.store.applyReportResult(DuelCall.Failure(Exception("500")), id, r.up) }
        assertTrue(r.store.connectionTrouble)
    }

    @Test
    fun rulesMismatchAsksForUpdate() = runTest {
        // 진행 중 판의 goal 이 엔진과 다르면 두지 않는다(CC-17). 기준선: goal 100 은 둔다.
        val r = rig(ME_B)
        val playing = action("crossy_duel_state__playing").state!!
        assertEquals(CrossyDuelStore.StateApplyOutcome.ignored, r.store.applyState(playing.copy(goal = 99), r.up))
        assertEquals(CrossyDuelAvailability.updateRequired, r.store.availability)
        assertNull(r.store.match)
        assertEquals(CrossyDuelStore.StateApplyOutcome.applied, r.store.applyState(playing, r.up))
    }

    // MARK: 로비

    @Test
    fun lightLobbyDoesNotWipeUsersOrRecord() = runTest {
        // 가벼운 로비(전적 null · users [])는 사람 목록·전적을 덮지 않는다(CS-4). 기준선: 전체 로비는 덮는다.
        val r = rig(ME_C)
        r.store.applyLobby(lobby("crossy_duel_lobby__ok"))
        val users = r.store.users
        assertEquals(12, users.size)
        assertEquals(CrossyDuelRecord(0, 0, 0), r.store.record)
        r.store.applyLobby(lobby("crossy_duel_lobby__light"))
        assertEquals(users, r.store.users)
        assertEquals(CrossyDuelRecord(0, 0, 0), r.store.record)
        assertEquals(100L, r.store.rubyBalance)
        r.store.applyLobby(lobby("crossy_duel_lobby__ok").copy(users = emptyList()))
        assertTrue(r.store.users.isEmpty(), "전체 로비의 빈 목록은 사실이다")
    }

    @Test
    fun duelsFlagOffSendsNoChallenge() = runTest {
        // 판돈 깃발이 꺼진 빌드(G §8-17 #1)는 신청 · 수락 요청을 내지 않는다. 기준선: 켜진 빌드는 낸다.
        val off = rig(ME_C, duels = false)
        off.store.challenge(ME_D, CrossyDuelStake.three)
        off.store.respond("00000000-0000-4000-8000-000000000001", accept = true)
        settle()
        assertEquals(0, off.server.calls.size)
        val on = rig(ME_C, duels = true)
        on.server.queue("crossy_duel_challenge", StubReply.Json(fixtureText(FIX, "crossy_duel_challenge__ok")))
        on.store.challenge(ME_D, CrossyDuelStake.three)
        settle()
        assertEquals(1, on.server.count("crossy_duel_challenge"))
        assertNotNull(on.store.outgoing)
        assertTrue(on.store.ownsMatch(on.store.outgoing!!.id), "신청한 기기가 그 판을 연 기기다")
    }

    @Test
    fun resumePointNeedsReportAfterStart() {
        val start = 1_000.0
        val after = CrossyDuelSideRow(seq = 3, score = 37, deaths = 2, ready = true, lastSeenMs = 2_000.0)
        assertEquals(CrossyDuelResumePoint(37, 2, 3), resumePoint(after, start))
        assertNull(resumePoint(after.copy(lastSeenMs = 900.0), start), "시작 전 보고만 있으면 새 판")
        assertNull(resumePoint(after.copy(ready = false), start))
    }
}

/** 시험에서 쓰는 보고 종류 줄임. */
private typealias CrossyDuelSessionKind = com.yehsung.aingcheck.core.rules.crossy.CrossyDuelSession.ReportKind

class CrossyDuelFrameLinkTest {
    private val me = "aaaaaaaa-0000-4000-8000-000000000001"
    private val them = "bbbbbbbb-0000-4000-8000-000000000002"

    private fun payload(vararg pairs: Pair<String, Any>): JsonObject = JsonObject(pairs.associate { (k, v) ->
        k to when (v) {
            is String -> JsonPrimitive(v)
            is Number -> JsonPrimitive(v)
            is Boolean -> JsonPrimitive(v)
            else -> error("?")
        }
    })

    @Test
    fun decodeKeepsFrameWhenGhostIsBroken() {
        val base = arrayOf<Pair<String, Any>>("v" to 1, "u" to them, "s" to 3, "f" to 10, "sc" to 42, "d" to 1, "h" to 200)
        val withGhost = CrossyDuelFrame.decode(payload(*base, "gx" to 412, "gr" to 42, "gf" to "left", "gd" to 0))
        val frame = (withGhost as CrossyDuelFrame.Decoded.Ok).frame
        assertEquals(CrossyDuelGhost(4.12, 42, CrossyGame.Direction.left, false), frame.ghost)
        // 그림자 칸이 깨지면 그림자만 버린다(점수 표시는 받는다). 기준선: 위 정상 칸은 그림자가 선다.
        val broken = CrossyDuelFrame.decode(payload(*base, "gx" to 412, "gr" to 42, "gf" to "sideways"))
        assertNull((broken as CrossyDuelFrame.Decoded.Ok).frame.ghost)
        // 불리언 · 소수는 정수가 아니다(Swift NSNumber 판정).
        assertEquals(CrossyDuelFrame.Decoded.Rejected(CrossyDuelFrameRejection.malformed), CrossyDuelFrame.decode(payload(*base.filter { it.first != "s" }.toTypedArray(), "s" to true)))
        assertEquals(CrossyDuelFrame.Decoded.Rejected(CrossyDuelFrameRejection.malformed), CrossyDuelFrame.decode(payload(*base.filter { it.first != "sc" }.toTypedArray(), "sc" to 4.5)))
        assertEquals(CrossyDuelFrame.Decoded.Rejected(CrossyDuelFrameRejection.unknownVersion), CrossyDuelFrame.decode(payload(*base.filter { it.first != "v" }.toTypedArray(), "v" to 2)))
        assertEquals(CrossyDuelFrame.Decoded.Rejected(CrossyDuelFrameRejection.outOfRange), CrossyDuelFrame.decode(payload(*base.filter { it.first != "sc" }.toTypedArray(), "sc" to 101)))
    }

    @Test
    fun payloadRoundTrips() {
        val link = CrossyDuelFrameLink(me, them, 1_000)
        link.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        val frame = link.makeFrame(10.0, 4, 30, 2, CrossyDuelGhost(3.456, 31, CrossyGame.Direction.forward, false))
        val back = (CrossyDuelFrame.decode(frame.payload) as CrossyDuelFrame.Decoded.Ok).frame
        assertEquals(frame.copy(ghost = frame.ghost!!.copy(x = 3.46)), back, "x 는 0.01 칸으로 실린다")
        assertEquals(1_001, link.nextFrameNumber)
    }

    @Test
    fun steadyNeedsThreeContinuousFramesWhileJoined() {
        val link = CrossyDuelFrameLink(me, them, 0)
        link.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        link.noteReportFailureStreak(0)
        assertEquals(CrossyDuelFrameSocketCommand.Connect("crossy_duel:m1", false), link.socketCommand(0.0, 0.0) { it })
        link.apply(RealtimeTransportEvent.Joined, 0.1) { it }
        fun frame(f: Long) = CrossyDuelFrame(them, 1, f, 10, 0, 300)
        assertNull(link.receive(frame(1), 1.0))
        assertNull(link.receive(frame(2), 2.0))
        assertFalse(link.conditions(2.0).allHold, "두 장은 아직 확인이 아니다")
        assertNull(link.receive(frame(3), 3.0))
        assertTrue(link.conditions(3.0).allHold)
        assertEquals(3.0, link.reportInterval(3.0), "확인됨 = 체크포인트 3초")
        assertEquals(CrossyDuelFrameRejection.stale, link.receive(frame(3), 3.5))
        // 2.5초 넘게 끊기면 ③ 이 거짓 — 곧바로 대체 길(보고 간격 = report_ms).
        assertFalse(link.conditions(6.0).allHold)
        assertEquals(2.0, link.reportInterval(6.0))
        assertEquals(CrossyDuelFrameRejection.notOpponent, link.receive(CrossyDuelFrame(me, 1, 9, 10, 0, 300), 6.0))
    }

    @Test
    fun ghostShowsOnlyWhileRecent() {
        val link = CrossyDuelFrameLink(me, them, 0)
        link.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        link.socketCommand(0.0, 0.0) { it }
        link.apply(RealtimeTransportEvent.Joined, 0.0) { it }
        val ghost = CrossyDuelGhost(4.0, 12, CrossyGame.Direction.forward, false)
        link.receive(CrossyDuelFrame(them, 1, 1, 10, 0, -1, ghost = ghost), 1.0)
        assertEquals(ghost, link.opponentGhost(2.0))
        assertNull(link.opponentGhost(3.6), "2.5초 넘은 그림자는 숨는다")
        link.receive(CrossyDuelFrame(them, 1, 2, 10, 1, -1, ghost = ghost.copy(dead = true)), 4.0)
        assertNull(link.opponentGhost(4.1), "죽어 있는 동안은 숨는다")
    }

    @Test
    fun frameCadence() {
        val link = CrossyDuelFrameLink(me, them, 0)
        link.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        link.socketCommand(0.0, 0.0) { it }
        assertFalse(link.frameDue(0.0, live = true, changed = true), "join 전에는 보내지 않는다")
        link.apply(RealtimeTransportEvent.Joined, 0.0) { it }
        assertTrue(link.frameDue(0.0, live = true, changed = false))
        link.makeFrame(0.0, 1, 0, 0)
        assertFalse(link.frameDue(0.3, live = true, changed = true))
        assertTrue(link.frameDue(0.3, live = true, changed = false, moved = true), "그림자가 움직이면 0.2초 틈")
        assertTrue(link.frameDue(0.5, live = true, changed = true), "바뀌면 0.5초 틈")
        assertFalse(link.frameDue(0.9, live = true, changed = false))
        assertTrue(link.frameDue(1.0, live = true, changed = false), "안 바뀌면 1초")
        assertFalse(link.frameDue(5.0, live = false, changed = true), "판이 흐르지 않으면 보내지 않는다")
    }

    @Test
    fun retriesThenStops() {
        val link = CrossyDuelFrameLink(me, them, 0)
        link.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        var now = 0.0
        repeat(CrossyDuelFrameLink.maxRetries) {
            assertTrue(link.socketCommand(now, 0.0) { it } is CrossyDuelFrameSocketCommand.Connect)
            assertEquals(CrossyDuelFrameSocketCommand.Disconnect, link.apply(RealtimeTransportEvent.Closed(null), now) { it })
            now += 10
        }
        assertTrue(link.socketCommand(now, 0.0) { it } is CrossyDuelFrameSocketCommand.Connect)
        link.apply(RealtimeTransportEvent.Closed(null), now) { it }
        assertEquals(CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.exhausted), link.socket)
        // RLS 거절은 재시도 없이 멈춘다.
        val denied = CrossyDuelFrameLink(me, them, 0)
        denied.noteServerFrames(CrossyDuelFramesRow(on = true, topic = "crossy_duel:m1"))
        denied.socketCommand(0.0, 0.0) { it }
        denied.apply(RealtimeTransportEvent.JoinRejected(com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection.Unauthorized), 0.0) { it }
        assertEquals(CrossyDuelFrameSocketPhase.Stopped(CrossyDuelFrameStopReason.unauthorized), denied.socket)
    }
}
