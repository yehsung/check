package com.aingcheck.games.data

import com.aingcheck.games.core.GameKind
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class GameRepositoryTest {
    private class MemoryVault : TokenStore {
        var value: String? = null
        override fun read() = value
        override fun save(refresh: String) { value = refresh }
        override fun clear() { value = null }
    }
    private lateinit var server: MockWebServer
    private lateinit var vault: MemoryVault
    private lateinit var repo: GameRepository
    @Before fun setup() {
        server = MockWebServer(); server.start()
        vault = MemoryVault()
        repo = GameRepository(GameApi(server.url("/").toString(), "anon"), vault)
    }
    @After fun cleanup() { server.shutdown() }
    private fun respond(body: String, code: Int = 200) = server.enqueue(MockResponse().setResponseCode(code).setBody(body))
    private fun session(access: String = "a", refresh: String = "r") =
        """{"access_token":"$access","refresh_token":"$refresh","user":{"id":"u"}}"""
    @Test fun privateProfileCannotStartOrSubmit() = runBlocking {
        respond(session()); repo.signIn("x", "y")
        respond("[{\"minigame_public\":false}]")
        try { repo.startRound(GameKind.TIMING); fail() } catch (_: ApiFailure) { }
        assertEquals(2, server.requestCount)
        respond("[{\"minigame_public\":false}]")
        try { repo.submit(GameKind.TIMING, 900, "token"); fail() } catch (_: ApiFailure) { }
        assertEquals(3, server.requestCount)
    }
    @Test fun rotatesRefreshTokenOnceAndRetries401WithNewAccess() = runBlocking {
        respond(session()); repo.signIn("x", "y")
        respond("", 401); respond(session("a2", "r2")); respond("[]")
        assertTrue(repo.board(GameKind.TIMING).isEmpty())
        assertEquals("r2", vault.value)
        server.takeRequest(); server.takeRequest()
        assertEquals("/auth/v1/token?grant_type=refresh_token", server.takeRequest().path)
        assertEquals("Bearer a2", server.takeRequest().getHeader("Authorization"))
    }
    @Test fun expiredSessionClearsStoredRefreshButNetworkFailureKeepsIt() = runBlocking {
        vault.value = "r"
        respond("", 503)
        try { repo.restore(); fail() } catch (_: ApiFailure) { }
        assertEquals("r", vault.value)
        respond("", 400)
        try { repo.restore(); fail() } catch (_: ApiFailure) { }
        assertNull(vault.value)
        assertNull(repo.userId)
    }
    @Test fun logoutClearsLocalIdentityWhenServerIsOffline() = runBlocking {
        respond(session()); repo.signIn("x", "y")
        respond("", 503); repo.signOut()
        assertNull(vault.value); assertNull(repo.userId)
    }
}
