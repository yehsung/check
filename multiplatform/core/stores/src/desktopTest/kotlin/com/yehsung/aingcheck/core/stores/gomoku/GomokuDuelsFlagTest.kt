// 원본: 없음 — G §8-17 #1(판돈 대결 Android 빌드 깃발 `duelsEnabled`, 소비는 W2-d·W2-e). iOS 에는 같은 깃발이 없다.
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * §8-17 #1: 판돈 대결의 **신청·수락 진입**은 앱 구성 깃발 `duelsEnabled` 가 꺼지면 스토어에서 막는다 — 신청 RPC 0 · 수락 RPC 0 · 받은 신청은
 * '앱 업데이트 필요' 꼴로 접는다. 켜지면 같은 흐름이 그대로 돈다. AI 대국·관전·순위는 깃발과 무관하다. 깃발은 [SessionContext.appConfig] →
 * [SessionGomokuHost] → 스토어 한 길로만 닿는다(마지막 시험이 실제 세션 스토어로 잰다).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuDuelsFlagTest {
    private val inboxCaller: String get() = gomokuUser("B")

    private fun TestScope.rig(duelsEnabled: Boolean, me: String = inboxCaller, configure: DuelStubServer.() -> Unit = {}):
        Triple<GomokuStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, AppConfig(duelsEnabled = duelsEnabled), clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        return Triple(store, host, server)
    }

    @Test
    fun lockedBuildSendsNoChallengeAndNoAccept() = runTest {
        val (store, _, server) = rig(duelsEnabled = false) {
            queueFixtures("gomoku_inbox", GOMOKU_FIXTURES, "gomoku_inbox__ok")
            queueFixtures("gomoku_respond", GOMOKU_FIXTURES, "gomoku_respond__decline_ok")
        }
        var arrived = 0
        store.onInviteArrived = { arrived += 1 }
        assertTrue(store.duelsLocked)

        store.challenge(gomokuUser("A"))
        settle()
        assertEquals(0, server.count("gomoku_challenge"), "깃발이 꺼진 빌드에서 신청 RPC 가 나갔다")
        assertEquals(GomokuNoticeText.updateMine, store.notice)
        assertNull(store.outgoing)
        // 화면 게이트는 스토어 게이트와 짝이다. 깃발 말고는 [도전]을 막을 까닭이 하나도 없는 자리에서 잰다
        // (받은함을 읽은 뒤에는 픽스처의 보낸 신청이 대신 막아 깃발 없이도 초록이 된다).
        val capable = GomokuUser("x", "x", null, null, isWorking = true, isCapable = true, inMatch = false)
        assertNull(store.match)
        assertFalse(store.isBusy)
        assertFalse(GomokuPhoneChallengeGate.isEnabled(capable, store), "화면 게이트가 스토어 게이트와 짝으로 막지 않는다")

        store.loadInbox()
        settle()
        // 받은 신청은 서버 사실 그대로 들되(코어 목록) 배너·점에서 빼고 한 줄로 접는다.
        assertEquals(2, store.incoming.size)
        assertTrue(store.pendingIncomingInvites.isEmpty(), "잠긴 빌드의 받은 신청이 배너·점 목록에 섰다")
        assertNull(store.bannerInvite)
        assertEquals(GomokuNoticeText.updateMine, store.incomingFoldedNotice)
        assertEquals(0, arrived, "수락할 수 없는 신청으로 도착 배너를 띄웠다")
        assertEquals(store.incoming.map { it.id }.toSet(), store.seenInviteIDs, "본 것으로는 적어야 깃발이 켜진 다음 빌드에서 두 번 안 뜬다")

        val first = store.incoming.first()
        store.respond(first.id, accept = true)
        settle()
        assertEquals(0, server.count("gomoku_respond"), "깃발이 꺼진 빌드에서 수락 RPC 가 나갔다")
        assertEquals(GomokuNoticeText.updateMine, store.notice)
        assertEquals(2, store.incoming.size)

        // 거절은 루비가 움직이지 않는 답이라 막지 않는다(상대에게 빨리 답이 간다).
        store.respond(first.id, accept = false)
        settle()
        assertEquals(1, server.count("gomoku_respond"))
        assertEquals(false, server.lastBody("gomoku_respond").bool("p_accept"))

    }

    @Test
    fun lockedBuildRematchSendsNothingAndKeepsTheResult() = runTest {
        val finished = GomokuServerFacts("gomoku_state__finished_loser_since0")
        val (store, _, server) = rig(duelsEnabled = false, me = finished.myID)
        store.applyState(decodeJson(JsonObject(fixtureJSON(GOMOKU_FIXTURES, "gomoku_state__finished_loser_since0") - "state"), GomokuStatePayload.serializer()))
        assertEquals(true, store.match?.isFinished)
        store.rematch()
        settle()
        assertEquals(0, server.count("gomoku_challenge"))
        assertEquals(GomokuNoticeText.updateMine, store.notice)
        assertEquals(GomokuPhase.result, store.phase, "막힌 다시 신청이 결과 화면을 걷었다")
        assertNotNull(store.match)
    }

    @Test
    fun unlockedBuildRunsTheSameFlow() = runTest {
        val (store, _, server) = rig(duelsEnabled = true) {
            queueFixtures("gomoku_inbox", GOMOKU_FIXTURES, "gomoku_inbox__ok")
            queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, "gomoku_challenge__ok")
            queueFixtures("gomoku_respond", GOMOKU_FIXTURES, "gomoku_respond__decline_ok")
        }
        var arrived = 0
        store.onInviteArrived = { arrived += 1 }
        assertFalse(store.duelsLocked)
        store.loadInbox()
        settle()
        assertEquals(2, store.pendingIncomingInvites.size)
        assertNotNull(store.bannerInvite)
        assertNull(store.incomingFoldedNotice)
        assertEquals(2, arrived)
        store.respond(store.incoming.first().id, accept = true)
        settle()
        assertEquals(1, server.count("gomoku_respond"))
        assertEquals(true, server.lastBody("gomoku_respond").bool("p_accept"))
        val capable = GomokuUser("x", "x", null, null, isWorking = true, isCapable = true, inMatch = false)
        assertTrue(GomokuPhoneChallengeGate.isEnabled(capable, store), "켜진 빌드에서 [도전]이 잠겼다")
        store.challenge(gomokuUser("A"))
        settle()
        assertEquals(1, server.count("gomoku_challenge"))
        assertNotNull(store.outgoing)
    }

    @Test
    fun aiRankingAndWatchIgnoreTheFlag() = runTest {
        val (store, _, server) = rig(duelsEnabled = false) {
            queueFixtures("gomoku_ranking", GOMOKU_FIXTURES, "gomoku_ranking__ok")
            queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__ok_since0")
        }
        store.spectatorFeaturesEnabled = true
        store.loadRanking()
        assertEquals(1, server.count("gomoku_ranking"))
        assertNotNull(store.ranking)
        store.startWatching(gomokuUser("m_watch"))
        store.refreshWatch()
        assertEquals(1, server.count("gomoku_watch_live"))
        assertEquals(true, store.spectating?.hasServerState)
        store.stopWatching()
        // AI 대국은 서버를 한 번도 타지 않는다 — 깃발과 무관하다.
        store.aiMoveChooser = { _, _ -> null }
        store.aiRuntime.minimumThinkSeconds = 0.0
        val before = server.calls.size
        assertTrue(store.canStartAIMatch)
        store.startAIMatch(GomokuColor.black)
        settle()
        assertTrue(store.isAIMatch)
        assertEquals(before, server.calls.size, "AI 판이 서버로 나갔다")
    }

    /** 실제 세션 스토어 + [SessionContext] 로 깃발을 넣는다 — 깃발이 스토어에 닿는 길은 이것 하나다. */
    private fun TestScope.sessionRig(appConfig: AppConfig): Triple<GomokuStore, DuelStubServer, SessionStore> {
        val server = DuelStubServer(this).queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, "gomoku_challenge__ok")
        val clock = SessionClock { contractClock }
        val sessionStore = SessionStore(
            service = server.service { contractClock },
            vault = InMemoryTokenVault(),
            prefs = MemoryKeyValueStore(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
            },
            clock = clock,
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() = Unit
            },
            parentScope = storeScope(),
        )
        sessionStore.adoptSignedInSession(SupabaseSession("access-token", "refresh-token", gomokuUser("C")), "c@test.invalid")
        val host = SessionGomokuHost(SessionContext(sessionStore, appConfig), ruby = RubyBalanceCell())
        val store = GomokuStore(storeScope(), host)
        return Triple(store, server, sessionStore)
    }

    @Test
    fun flagReachesTheStoreThroughSessionContext() = runTest {
        val (locked, lockedServer, _) = sessionRig(AppConfig(duelsEnabled = false))
        assertTrue(locked.duelsLocked)
        locked.challenge(gomokuUser("A"))
        settle()
        assertEquals(0, lockedServer.count("gomoku_challenge"))
        assertEquals(GomokuNoticeText.updateMine, locked.notice)

        val (open, openServer, _) = sessionRig(AppConfig(duelsEnabled = true))
        assertFalse(open.duelsLocked)
        open.challenge(gomokuUser("A"))
        settle()
        assertEquals(1, openServer.count("gomoku_challenge"))
        assertEquals("신청을 보냈어요", open.notice)
        // 기본값은 꺼짐이다(§8-17 #1 — 켜는 것은 빌드 N 의 조립 지점 몫).
        assertFalse(AppConfig().duelsEnabled)
    }
}

/** 메모리 설정 저장소(시험용). */
class MemoryKeyValueStore : KeyValueStore {
    private val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
