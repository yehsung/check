package com.yehsung.aingcheck.android.routing

import android.content.Intent
import com.yehsung.aingcheck.android.routing.RouteIntents.Incoming
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RouteIntentsTest {
    private val proof = "f".repeat(64)
    private fun open(route: String?, accept: Boolean, proofExtra: String?) =
        Incoming(RouteIntents.ACTION_OPEN_ROUTE, dataString = null, routeExtra = route, acceptExtra = accept, proofExtra = proofExtra)

    @Test
    fun viewDeepLinkOpensRouteButNeverAccepts() {
        val viaView = Incoming(Intent.ACTION_VIEW, "aingcheck://gomoku/invite/m1", routeExtra = null, acceptExtra = true, proofExtra = proof)
        assertEquals(RouteRequest(AingRoute.GomokuInvite("m1"), accept = false), RouteIntents.parse(viaView, proof))
    }

    @Test
    fun acceptNeedsTheInstallProof() {
        val url = AingRoute.ChessInvite("c1").url
        assertEquals(RouteRequest(AingRoute.ChessInvite("c1"), accept = true), RouteIntents.parse(open(url, true, proof), proof))
        // 증표가 틀리거나 없으면 화면만 연다(다른 앱이 보낸 명시적 Intent).
        assertEquals(RouteRequest(AingRoute.ChessInvite("c1"), accept = false), RouteIntents.parse(open(url, true, "0".repeat(64)), proof))
        assertEquals(RouteRequest(AingRoute.ChessInvite("c1"), accept = false), RouteIntents.parse(open(url, true, null), proof))
        // 이 설치의 증표를 못 만들었으면(빈 값) 빈 증표도 통과하지 않는다.
        assertFalse(RouteIntents.parse(open(url, true, ""), "")!!.accept)
        assertFalse(RouteIntents.parse(open(url, true, ""), null)!!.accept)
    }

    /** G §8-13: 최근 앱(기록)에서 다시 온 작업 뿌리 Intent 는 증표가 맞아도 수락이 아니다 — 화면은 연다. */
    @Test
    fun historyRelaunchNeverAccepts() {
        val url = AingRoute.GomokuInvite("m1").url
        val replay = open(url, true, proof).copy(launchedFromHistory = true)
        assertEquals(RouteRequest(AingRoute.GomokuInvite("m1"), accept = false), RouteIntents.parse(replay, proof))
        // 기준선: 같은 증표·같은 라우트라도 기록 표시가 없으면 수락이다.
        assertTrue(RouteIntents.parse(replay.copy(launchedFromHistory = false), proof)!!.accept)
    }

    @Test
    fun acceptOnlyForInvites() {
        assertFalse(RouteIntents.parse(open(AingRoute.Message("p").url, true, proof), proof)!!.accept)
        assertTrue(RouteIntents.parse(open(AingRoute.GomokuInvite("m").url, true, proof), proof)!!.accept)
    }

    @Test
    fun launcherAndGarbageChangeNothing() {
        assertNull(RouteIntents.parse(Incoming(Intent.ACTION_MAIN, null, null, false, null), proof))
        assertNull(RouteIntents.parse(open("aingcheck://nope", false, null), proof))
        assertNull(RouteIntents.parse(Incoming(Intent.ACTION_VIEW, "https://evil/message/x", null, false, null), proof))
        assertNull(RouteIntents.parse(Incoming(null, null, null, false, null), proof))
    }

    @Test
    fun proofIsStableAndPerInstall() {
        val storeA = MapStore()
        val a1 = RouteProof(storeA).value()
        val a2 = RouteProof(storeA).value()
        val b = RouteProof(MapStore()).value()
        assertEquals(64, a1!!.length)
        assertEquals(a1, a2)
        assertNotEquals(a1, b)
        // 저장소에 못 쓰면 증표가 없다(수락 버튼을 싣지 않는다).
        assertNull(RouteProof(MapStore(failWrites = true)).value())
    }

    private class MapStore(private val failWrites: Boolean = false) : KeyValueStore {
        private val m = HashMap<String, Any>()
        override fun getString(key: String) = m[key] as? String
        override fun putString(key: String, value: String) { if (!failWrites) m[key] = value }
        override fun getLong(key: String) = m[key] as? Long
        override fun putLong(key: String, value: Long) { if (!failWrites) m[key] = value }
        override fun getBoolean(key: String) = m[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { if (!failWrites) m[key] = value }
        override fun remove(key: String) { m.remove(key) }
    }
}
