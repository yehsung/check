// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift:873-875 @ 3bd04bd (dismiss() 뒤 Task { await tetris.challenge } — 시트가 사라져도 요청은 산다)
//
// 판돈 신청이 사라지던 결함: 시트가 닫히는 순간 신청 코루틴이 같이 취소되면 판이 안 생기고 알림도 안 뜬다.
// 요청이 서버에서 머무는 동안 시트를 닫고, 응답이 온 뒤 보낸 신청이 서는지 잰다.
package com.yehsung.aingcheck.android.screens.games.tetris

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.android.screens.games.gomoku.DEST_ME
import com.yehsung.aingcheck.android.screens.games.gomoku.DEST_RIVAL
import com.yehsung.aingcheck.android.screens.games.gomoku.DestinationTestRig
import com.yehsung.aingcheck.android.screens.games.gomoku.destinationClock
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelScreen
import com.yehsung.aingcheck.ui.games.tetris.TetrisDuelTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.engine.HttpClientEngineBase
import io.ktor.client.engine.HttpClientEngineCapability
import io.ktor.client.engine.HttpClientEngineConfig
import io.ktor.client.engine.callContext
import io.ktor.client.plugins.HttpTimeoutCapability
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpProtocolVersion
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.util.date.GMTDate
import io.ktor.utils.io.ByteReadChannel
import io.ktor.utils.io.InternalAPI
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** tetris_challenge 는 [gate] 가 열릴 때까지 서버에 머문다. 그 밖의 호출(로비 · 폴링)은 응답 없이 머문다 — 이 시험은 신청만 잰다. */
private class ChallengeGateEngine(private val responseBody: String) : HttpClientEngineBase("tetris-stake-gate") {
    override val config: HttpClientEngineConfig = HttpClientEngineConfig()
    override val supportedCapabilities: Set<HttpClientEngineCapability<*>> = setOf(HttpTimeoutCapability)
    val gate = CompletableDeferred<Unit>()

    @Volatile var challenges = 0

    @InternalAPI
    override suspend fun execute(data: HttpRequestData): HttpResponseData {
        if (!data.url.encodedPath.endsWith("/tetris_challenge")) awaitCancellation()
        challenges += 1
        gate.await()
        return HttpResponseData(
            HttpStatusCode.OK, GMTDate(), headersOf(HttpHeaders.ContentType, "application/json"),
            HttpProtocolVersion.HTTP_1_1, ByteReadChannel(responseBody), callContext(),
        )
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w400dp-h900dp-xhdpi")
class TetrisStakeSendTest {
    private val nowMs = (destinationClock.timeIntervalSince1970 * 1000).toLong()
    private val lobby = """
        {"status":"ok","server_now_ms":$nowMs,"stakes":[3,5,10],"matches":[],
        "me":{"active_match_id":null,"incoming":[],"outgoing":null,"wins":0,"losses":0,"draws":0},
        "users":[{"id":"$DEST_RIVAL","display_name":"서연","avatar_url":null,"character":null,"is_working":true,"capable":true,"in_match":false,"focus_mode":false}]}
    """.trimIndent()
    private val challengeOk = """{"status":"ok","match_id":"out-1","expires_at_ms":${nowMs + 60_000},"server_now_ms":$nowMs,"ruby_balance":100}"""

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun challengeOutlivesTheStakeSheet() = runComposeUiTest {
        val engine = ChallengeGateEngine(challengeOk)
        val rig = DestinationTestRig(DEST_ME, engine)
        runBlocking { rig.tetris.applyLobby(SwiftJson.decode(TetrisLobbyResponse.serializer(), lobby)) }
        setContent { AingTheme(dark = false) { GamesTetrisDuelScreen(rig.games, myUserID = DEST_ME, refreshHz = 60) } }
        fun drainStore() { while (true) (rig.dispatcher.parked.removeFirstOrNull() ?: return).run() }
        waitForIdle()
        onNode(hasTestTag(TetrisDuelTags.challenge(DEST_RIVAL))).performClick()
        waitForIdle()
        onNode(hasTestTag(TetrisDuelTags.stake(5))).performClick()
        waitForIdle()
        onNode(hasTestTag(TetrisDuelTags.STAKE_SEND)).performClick()
        waitForIdle() // 시트가 컴포지션에서 빠진다 — 응답은 아직 안 왔다.
        onNode(hasTestTag(TetrisDuelTags.STAKE_SEND)).assertDoesNotExist()

        engine.gate.complete(Unit)
        repeat(400) {
            drainStore()
            if (rig.tetris.outgoing != null) return@repeat
            Thread.sleep(5)
        }
        assertNotNull("시트가 닫히며 신청이 취소됐다 — 판이 안 생기고 알림도 없다(서버까지 간 요청 ${engine.challenges}건)", rig.tetris.outgoing)
        assertEquals("신청 요청 수", 1, engine.challenges)
        assertFalse("신청 뒤 isBusy 가 남았다", rig.tetris.isBusy)
        rig.scope.cancel()
    }
}
