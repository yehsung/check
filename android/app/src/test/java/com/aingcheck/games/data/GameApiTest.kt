package com.aingcheck.games.data

import com.aingcheck.games.core.GameKind
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class GameApiTest {
    private lateinit var server: MockWebServer
    private lateinit var api: GameApi
    private val session = Session("access", "refresh", "user-1")
    @Before fun setup() { server = MockWebServer(); server.start(); api = GameApi(server.url("/").toString(), "anon") }
    @After fun cleanup() { server.shutdown() }
    private fun respond(body: String, code: Int = 200) = server.enqueue(MockResponse().setResponseCode(code).setBody(body))
    @Test fun loginAndRefreshUseCorrectGrantAndNeverChangePassword() {
        val response = """{"access_token":"access","refresh_token":"refresh","user":{"id":"user-1"}}"""
        respond(response)
        assertEquals(session, api.signIn(" user@example.com ", " p a s s "))
        val login = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=password", login.path)
        val body = JSONObject(login.body.readUtf8())
        assertEquals("user@example.com", body.getString("email"))
        assertEquals(" p a s s ", body.getString("password"))
        respond(response); api.refresh("refresh")
        val refresh = server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=refresh_token", refresh.path)
        assertEquals("refresh", JSONObject(refresh.body.readUtf8()).getString("refresh_token"))
    }
    @Test fun privacyIsClosedForMissingFalseOrNull() {
        listOf("[]", "[{}]", "[{\"minigame_public\":null}]", "[{\"minigame_public\":false}]").forEach {
            respond(it); assertFalse(api.isPublic(session))
        }
        respond("[{\"minigame_public\":true}]"); assertTrue(api.isPublic(session))
    }
    @Test fun scoreUsesRpcAndMatchingToken() {
        respond("""{"status":"ok","token":"round-1"}""")
        assertEquals("round-1", api.startRound(session, GameKind.TIMING))
        assertEquals("/rest/v1/rpc/minigame_start_round", server.takeRequest().path)
        respond("""{"status":"ok","best_score":900,"improved":true}""")
        assertEquals(900, api.submit(session, GameKind.TIMING, 850, "round-1").bestScore)
        val request = server.takeRequest()
        assertEquals("/rest/v1/rpc/minigame_submit_score", request.path)
        assertEquals("Bearer access", request.getHeader("Authorization"))
        val json = JSONObject(request.body.readUtf8())
        assertEquals("timing_bar", json.getString("p_game"))
        assertEquals(850, json.getInt("p_score"))
        assertEquals("round-1", json.getString("p_token"))
    }
    @Test fun rejectsRefusedRoundAndInvalidScoreBeforeNetwork() {
        respond("""{"status":"unauthorized"}""")
        try { api.startRound(session, GameKind.FLAPPY); fail() } catch (_: ApiFailure) { }
        assertEquals(1, server.requestCount)
        try { api.submit(session, GameKind.FLAPPY, 1000, "token"); fail() } catch (_: IllegalArgumentException) { }
        assertEquals(1, server.requestCount)
    }
    @Test fun boardHandlesOptionalFieldsAndSortsScores() {
        respond("""[{"user_id":"a","best_score":4},{"user_id":"b","display_name":"아잉","best_score":9}]""")
        val board = api.board(session, GameKind.FLAPPY)
        assertEquals(listOf(9, 4), board.map { it.score })
        assertEquals("사용자", board.last().name)
        assertFalse(JSONObject(server.takeRequest().body.readUtf8()).has("p_day"))
    }
    @Test fun failuresDoNotExposeResponseOrRetryMutations() {
        respond("sensitive-response", 401)
        try { api.startRound(session, GameKind.TIMING); fail() } catch (error: ApiFailure) {
            assertEquals(401, error.status)
            assertFalse(error.message!!.contains("sensitive"))
        }
        assertEquals(1, server.requestCount)
    }
    @Test fun tiedScoresUseActualTimestampBeforeName() {
        respond("""[{"user_id":"later","display_name":"가","best_score":9,"best_at":"2026-10-27T01:00:00.500Z"},{"user_id":"earlier","display_name":"나","best_score":9,"best_at":"2026-10-27T01:00:00Z"},{"user_id":"unknown","best_score":9}]""")
        assertEquals(listOf("earlier", "later", "unknown"), api.board(session, GameKind.TIMING).map { it.userId })
    }
}
