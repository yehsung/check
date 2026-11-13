// 원본: Tests/checkTests/V03xxMahjongWireContractTests.swift(픽스처 계약) · V03xxMahjongStoreTests.swift · V03xxMahjongPracticeTests.swift @ e4995a3a — Android 판 8
// 아잉 마작 와이어 실응답 67 디코드 · 스토어 가드 · 방 만들기 → 판 · 혼자 연습판 한 판 끝까지.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.StubReply
import com.yehsung.aingcheck.core.stores.gomoku.contractClock
import com.yehsung.aingcheck.core.stores.gomoku.fixtureText
import com.yehsung.aingcheck.core.stores.gomoku.settle
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val MJ = "Tests/checkTests/Fixtures/mahjong-rpc"

@OptIn(ExperimentalCoroutinesApi::class)
class MahjongStoreTest {
    private fun manifestFiles(): Map<String, String> {
        val m = Json.parseToJsonElement(RepoFiles.readText("$MJ/_manifest.json")) as JsonObject
        return (m["files"] as JsonObject).mapValues { (it.value as JsonPrimitive).content }
    }

    // 없으면: 서버가 실제로 내는 응답(로비 · 방 · 판 · 화료 · 자리 비움 · 거절 67)을 Android 가 못 읽어도 시험은 초록이다.
    @Test
    fun everyServerFixtureDecodesWithKnownStatus() {
        val files = manifestFiles()
        assertEquals(67, files.size)
        val failures = mutableListOf<String>()
        for ((name, md5) in files) {
            val text = RepoFiles.readText("$MJ/$name")
            val got = MessageDigest.getInstance("MD5").digest(text.encodeToByteArray()).joinToString("") { "%02x".format(it) }
            if (got != md5) failures += "$name: md5"
            try {
                val status = when {
                    name.startsWith("mahjong_lobby") -> SwiftJson.decode(MahjongLobbyResponse.Serializer, text).status
                    name.startsWith("mahjong_ranking") -> SwiftJson.decode(MahjongRankingResponse.Serializer, text).status
                    else -> SwiftJson.decode(MahjongActionResponse.Serializer, text).also { r ->
                        // 판 state 가 실렸으면 내 결정 · 사건까지 읽혀야 한다(모르는 결정 kind 만 null 로 접는다).
                        val raw = (Json.parseToJsonElement(text) as JsonObject)["state"] as? JsonObject
                        if (raw?.get("my_decision") is JsonObject && r.state?.myDecision == null) failures += "$name: my_decision 을 못 읽음"
                    }.status
                }
                if (status == MahjongRPCStatus.unknown) failures += "$name: status unknown"
            } catch (e: Exception) {
                failures += "$name: ${e.message}"
            }
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    @Test
    fun turnFixtureCarriesDecisionAndHand() {
        val r = SwiftJson.decode(MahjongActionResponse.Serializer, fixtureText(MJ, "mahjong_state__turn_mine"))
        val state = assertNotNull(r.state)
        val turn = state.myDecision as? MahjongDecision.Turn
        assertNotNull(turn)
        assertTrue(turn.discard.isNotEmpty())
        assertEquals(4, state.seats?.size)
        assertTrue((state.myHand?.size ?: 0) >= 1)
        val claim = SwiftJson.decode(MahjongActionResponse.Serializer, fixtureText(MJ, "mahjong_state__claim_option")).state?.myDecision
        assertTrue(claim is MahjongDecision.Call)
    }

    private fun TestScope.serverStore(me: String, server: DuelStubServer): MahjongStore {
        val host = FakeDuelHost(server.service { contractClock }, me, clockNow = { contractClock })
        return MahjongStore(host, storeScope(), clock = { contractClock }, botContext = coroutineContext.minusKey(kotlinx.coroutines.Job)).also {
            it.timersEnabled = false
            it.pollStepSeconds = 3_600.0
        }
    }

    private fun meOf(fixture: String): String {
        val s = (Json.parseToJsonElement(fixtureText(MJ, fixture)) as JsonObject)["state"] as JsonObject
        val host = ((s["match"] as JsonObject)["host"] as JsonObject)["id"] as JsonPrimitive
        return host.content
    }

    // 없으면: 방 만들기 응답이 방을 세우지 않거나 이 기기 판으로 안 적어도(장부) 알림 · 깨우기가 안 돈다.
    @Test
    fun createRoomStandsTheRoomAndNotesOwnership() = runTest {
        val server = DuelStubServer(this).queueFixtures("mahjong_create", MJ, "mahjong_create__ok")
            .queueFixtures("mahjong_lobby", MJ, "mahjong_lobby__ok", "mahjong_lobby__ok")
        val store = serverStore(meOf("mahjong_create__ok"), server)
        store.createRoom()
        settle()
        assertEquals(MahjongPhase.room, store.phase)
        val id = assertNotNull(store.match?.match?.id)
        assertTrue(store.ownsMatch(id))
        assertTrue(store.isHost)
        assertEquals(false, store.canStart)
        assertEquals(1, server.count("mahjong_create"))
        assertEquals("tonpuu", (server.lastBody("mahjong_create")["p_format"] as JsonPrimitive).content)
    }

    // 없으면: 판돈 대결 스위치가 꺼져도 방 만들기 · 참가가 나가 루비가 걸린다(G §8-17 #1).
    @Test
    fun duelsOffBlocksCreateAndJoin() = runTest {
        val server = DuelStubServer(this)
        val host = FakeDuelHost(server.service { contractClock }, "0e57a3c9-f9a2-4f0c-b585-d78604e285e5", com.yehsung.aingcheck.core.session.app.AppConfig(duelsEnabled = false), clockNow = { contractClock })
        val store = MahjongStore(host, storeScope(), clock = { contractClock }).also { it.timersEnabled = false }
        store.createRoom()
        store.join(com.yehsung.aingcheck.core.wire.SwiftUUID.parse("0e57a3c9-f9a2-4f0c-b585-d78604e285e5")!!)
        settle()
        assertEquals(0, server.count("mahjong_create"))
        assertEquals(0, server.count("mahjong_join"))
    }

    // 없으면: 늦게 온 옛 seq 응답이 새 판을 덮어 버린 패가 손으로 돌아온다(가드 (c)).
    @Test
    fun olderSeqOfSameMatchIsIgnored() = runTest {
        val store = MahjongStore(null, storeScope(), clock = { contractClock }).also { it.timersEnabled = false }
        val newer = SwiftJson.decode(MahjongActionResponse.Serializer, fixtureText(MJ, "mahjong_state__turn_mine")).state!!
        val older = newer.copy(match = newer.match!!.copy(seq = (newer.match!!.seq ?: 1) - 1), myHand = emptyList())
        assertEquals(MahjongStateApplyOutcome.applied, store.applyState(newer))
        assertEquals(MahjongStateApplyOutcome.ignored, store.applyState(older))
        assertEquals(newer.myHand, store.match?.myHand)
        assertEquals(MahjongPhase.playing, store.phase)
    }

    // 없으면: 울기에 답한 뒤 늦게 온 answered == null 조회가 프롬프트를 되살려 같은 창에 두 번 답한다(가드 (h)).
    @Test
    fun answeredWindowStaysAnswered() = runTest {
        val store = MahjongStore(null, storeScope(), clock = { contractClock }).also { it.timersEnabled = false }
        val claim = SwiftJson.decode(MahjongActionResponse.Serializer, fixtureText(MJ, "mahjong_state__claim_option")).state!!
        val call = claim.myDecision as MahjongDecision.Call
        store.noteCallAnswered(claim.match!!.id, call.windowId, "pass")
        store.applyState(claim)
        assertEquals("pass", (store.match?.myDecision as MahjongDecision.Call).answered)
        assertNull(store.openServerCall)
    }

    // 없으면: 접은 방의 늦은 응답이 방을 되살린다(가드 (a)).
    @Test
    fun dismissedRoomStaysDismissed() = runTest {
        val store = MahjongStore(null, storeScope(), clock = { contractClock }).also { it.timersEnabled = false }
        val room = SwiftJson.decode(MahjongActionResponse.Serializer, fixtureText(MJ, "mahjong_state__room")).state!!
        store.applyState(room)
        assertEquals(MahjongPhase.room, store.phase)
        store.leaveHeldRoom(room.match!!.id)
        assertEquals(MahjongPhase.lobby, store.phase)
        assertEquals(MahjongStateApplyOutcome.ignored, store.applyState(room))
        assertNull(store.match)
    }

    // 없으면: 혼자 연습판이 봇 차례 · 울기 창 · 미룬 쯔모 · 다음 국 어디선가 멎어도 모른다(서버도 루비도 없이 끝까지 가야 한다).
    @Test
    fun practiceGameRunsToTheEndWithBots() = runTest {
        val store = MahjongStore(null, storeScope(), clock = { SwiftDate(1_900_000_000.0 + testScheduler.currentTime / 1000.0) }, botContext = coroutineContext.minusKey(kotlinx.coroutines.Job))
        store.timersEnabled = false
        store.practiceRuntime.delayScale = 0.0
        store.practiceRuntime.pickHumanSeat = { 0 }
        var wallSeed = 0uL
        store.practiceRuntime.makeWall = { MahjongBotPlay.wall(com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom(77uL + wallSeed++)) }
        store.practiceRuntime.nextSeed = { 5uL }
        store.windowDidShow()
        store.startPractice(MahjongFormat.tonpuu, timed = false)
        assertTrue(store.isPractice)
        assertEquals(MahjongPhase.playing, store.phase)
        var humanMoves = 0
        var steps = 0
        while (store.phase == MahjongPhase.playing && steps < 5_000) {
            steps += 1
            runCurrent()
            advanceTimeBy(50)
            runCurrent()
            when (val d = store.myDecision) {
                is MahjongDecision.Turn -> {
                    val tile = store.table?.myDrawn?.takeIf { it in d.discard } ?: d.discard.last()
                    store.discard(tile)
                    humanMoves += 1
                }
                is MahjongDecision.Call -> if (d.answered == null) {
                    store.passCall()
                    humanMoves += 1
                }
                null -> Unit
            }
        }
        assertEquals(MahjongPhase.finished, store.phase, "steps $steps")
        assertTrue(humanMoves > 10)
        assertEquals(0, store.practiceRuntime.droppedBotMoves)
        assertNotEquals(0, store.practiceRuntime.botCalls)
        val seats = store.table?.seats ?: emptyList()
        assertEquals(setOf(1, 2, 3, 4), seats.mapNotNull { it.finalRank }.toSet())
        assertNull(store.match)
        assertEquals(null, store.notice?.takeIf { it == MahjongNoticeText.notAnOption })
    }

    // 없으면: 화면이 가려진 동안에도 연습판 봇이 계속 둬서 돌아오면 판이 한참 지나 있다.
    @Test
    fun practicePausesWhileHidden() = runTest {
        val store = MahjongStore(null, storeScope(), clock = { contractClock }, botContext = coroutineContext.minusKey(kotlinx.coroutines.Job))
        store.timersEnabled = false
        store.practiceRuntime.delayScale = 0.0
        store.practiceRuntime.pickHumanSeat = { 2 }
        store.practiceRuntime.makeWall = { MahjongBotPlay.wall(com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom(3uL)) }
        store.startPractice(MahjongFormat.tonpuu, timed = false)
        assertEquals(true, store.practice?.isPaused)
        val seq = store.practice?.payload?.match?.seq
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(seq, store.practice?.payload?.match?.seq)
        store.windowDidShow()
        advanceTimeBy(5_000)
        runCurrent()
        assertNotEquals(seq, store.practice?.payload?.match?.seq)
    }
}
