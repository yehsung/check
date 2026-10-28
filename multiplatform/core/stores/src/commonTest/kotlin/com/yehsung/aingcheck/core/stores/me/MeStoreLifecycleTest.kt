// 원본: Tests/CheckMobileKitTests/MeStoreTests.swift · MeStoreRaceTests.swift · MeTokenShareTests.swift(계정 교체 · 로그아웃 경합 · 공유 비율 캐시) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeStoreLifecycleTest {
    private val status = MeFixtures.fixture("_me/rpc.achievements_status.json")
    private val claimAll = MeFixtures.fixture("_me/rpc.achievement_claim.json")
    private val pending = MeFixtures.fixture("rpc.character_gift_pending@demo-gift.json")
    private val sessions = MeFixtures.fixture("rest.work_sessions.get@limit=5000.json")
    private val settings = MeFixtures.fixture("rest.profiles.get@token_usage_collect.json")

    private val shop = """{"ruby_balance":120,"characters":[],"gacha":{"price":50,"shards":3,"odds":[{"character_id":"fox","percent":100}],"shard_costs":{"fox":2}}}"""

    @Test
    fun signOutDropsALateClaimAnswerAndResetClearsEveryAccountBoundValue() = runTest {
        val claimGate = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "achievement_claim" -> MeReply.Gate(claimGate, MeReply.Json(claimAll))
                "shop_state" -> MeReply.Json(shop)
                "gacha_pull" -> MeReply.Offline
                "character_gift_pending" -> MeReply.Json(pending)
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        h.store.launch { h.store.loadShop() }
        h.store.launch { h.store.loadCakeGift() }
        runCurrent()
        h.store.pullGacha() // 결과 모름 — id 를 쥔다
        runCurrent()
        h.store.cakeGiftSheetDidAppear()
        val shownGift = h.store.cakeGiftSheet!!.id
        h.store.claimAllAchievements() // 문에서 멈춘다
        runCurrent()
        assertNotNull(h.store.gachaRequestIDs.pull)
        val writesBefore = h.ruby.rubyWriteSerial

        h.sessionStore.signOut()
        h.store.reset() // 앱 모델이 세대가 오른 뒤 부르는 자리
        claimGate.complete(Unit)
        runCurrent()

        assertNull(h.store.achievements, "늦게 온 받기 응답이 다음 계정 화면에 서지 않는다")
        assertEquals(writesBefore, h.ruby.rubyWriteSerial, "앞 계정의 잔량을 미러에 쓰지 않는다")
        assertEquals(emptySet(), h.store.achievementClaimsInFlight, "떠 있던 받기 자리가 남아 새 계정의 첫 받기를 막지 않는다")
        assertNull(h.store.gachaRequestIDs.pull, "앞 사람의 request_id 로 다음 사람이 뽑지 않는다")
        assertNull(h.store.gachaInfo)
        assertNull(h.store.cakeGift)
        assertNull(h.store.cakeGiftSheet)
        assertEquals(setOf(MeCharacterCards.aingID), h.store.ownedCharacterIDs)
        assertTrue(shownGift in h.store.cakeGiftAutoShownIDs, "스스로 띄운 기록은 **실행** 단위 — 로그아웃에도 남는다")
        assertFalse(h.store.shopState.hasLoaded)
        assertTrue(h.store.achievementsAvailable && h.store.dailyMissionsAvailable && h.store.weeklyWorkAvailable)
        h.assertClean()
    }

    @Test
    fun recordsKeepTheSharedCodexRatioCacheAcrossThrottleAndFailures() = runTest {
        var boardDown = false
        val daily = """[{"day":"2026-09-15","device_id":"mac-1","claude_total":100,"codex_total":10,"codex_utc_total":10,"codex_account":1000},
                        {"day":"2026-09-16","device_id":"mac-1","claude_total":200,"codex_total":0,"codex_utc_total":0,"codex_account":null}]"""
        val board = """[{"user_id":"user-1","display_name":"나","avatar_url":null,"claude_input":1,"claude_output":1,"claude_cache_read":0,
            "claude_cache_creation":0,"codex_input":5,"codex_output":5,"total":262,"today_total":0,"today_date":"2026-09-17","codex_cache_read":0,
            "codex_account_month":250,"codex_effective":260}]"""
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/work_sessions" -> MeReply.Json(sessions)
                r.method == "GET" && r.path == "/rest/v1/profiles" -> MeReply.Json(settings)
                r.method == "GET" && r.path == "/rest/v1/token_usage_device_daily" -> MeReply.Json(daily)
                r.rpcName == "token_usage_board" -> if (boardDown) MeReply.serverDown else MeReply.Json(board)
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadRecords() }
        advanceUntilIdle()
        assertTrue(h.store.recordsState.hasLoaded)
        assertEquals(0.25, h.store.tokenShareRatio, "내 몫 250 / 계정 버킷 1000")
        assertEquals("0.25", h.prefs.getString("aing.me.codexShareRatio.user-1"), "계정별 키로 영속한다")
        // 계정 버킷 1000 은 0.25 를 곱해 250 — 그날 칸 = claude 100 + Codex 유효(250).
        assertEquals(350L + 200L, h.store.tokenGrid.totalTokens)
        assertEquals(60L * 3600, assertNotNull(h.store.retroForDisplay, "지난주 세션이 있다").goalSeconds, "팀이 없으면 기본 목표(60시간)")

        h.store.launch { h.store.loadRecords() } // 300초 안 — 보드는 다시 안 묻는다
        advanceUntilIdle()
        assertEquals(1, h.server.count("token_usage_board"))

        advanceTimeBy(301_000)
        boardDown = true
        h.store.launch { h.store.loadRecords() }
        advanceUntilIdle()
        assertEquals(2, h.server.count("token_usage_board"))
        assertEquals(0.25, h.store.tokenShareRatio, "실패는 캐시를 지킨다(1.0 으로 되돌리면 잔디가 최대 19배로 되부푼다)")
        assertTrue(h.store.recordsState.hasLoaded && !h.store.recordsState.hasFailed, "비율 실패가 잔디를 비우지 않는다")
        h.assertClean()
    }
}
