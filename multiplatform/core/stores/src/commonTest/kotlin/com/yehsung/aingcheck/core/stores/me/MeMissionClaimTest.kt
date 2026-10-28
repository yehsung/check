// 원본: Tests/CheckMobileKitTests/MeAchievementClaimTests.swift · MeDailyMissionStoreTests.swift · MeWeeklyWorkTests.swift · MeShopRubyRollbackTests.swift(주간·미션 [받기] 의 잔량 반영 순서) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * 문(Gate)을 쓰는 시험은 `advanceUntilIdle()` 대신 `runCurrent()` 로만 흘린다 — 가상 시계를 앞으로 돌리면 HttpTimeout(30초)이 닫힌 문의
 * 요청을 먼저 끊어, "늦게 도착한 응답" 대신 "실패한 응답"을 재게 된다(그러면 받기 도장 가드를 빼도 초록이다 — 결함 심기로 확인).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MeMissionClaimTest {
    private val status = MeFixtures.fixture("_me/rpc.achievements_status.json")
    private val claimTodo3 = MeFixtures.fixture("_me/rpc.achievement_claim@todo3.json")
    private val claimAll = MeFixtures.fixture("_me/rpc.achievement_claim.json")
    private val dailyGomoku = MeFixtures.fixture("_me/rpc.daily_mission_claim@daily_gomoku.json")
    private val weeklyStatus = MeFixtures.fixture("_me/rpc.weekly_work_status.json")
    private val weeklyClaim = MeFixtures.fixture("_me/rpc.weekly_work_claim.json")

    private fun shop(ruby: Long) = """{"ruby_balance":$ruby,"characters":[]}"""

    private fun edit(json: String, block: (MutableMap<String, JsonElement>) -> Unit): String {
        val top = Json.parseToJsonElement(json).jsonObject.toMutableMap()
        block(top)
        return JsonObject(top).toString()
    }

    private fun bodyKey(body: String): String = body.substringAfter("\"p_key\":").substringBefore('}').trim()

    // ③ 받기 응답이 옮겨진 뒤 도착한 **받기 전** 조회는 버린다 · 잔량은 받기 응답의 값

    @Test
    fun statusFetchThatLeftBeforeTheClaimIsDroppedWhenItArrivesAfter() = runTest {
        // 받기는 서버에서 먼저 정산을 돌린다 — 그 응답에는 minigame3 의 **새 달성**이 들어 있다. 받기 전에 떠난 조회(minigame3 미달성)를
        // 그대로 덮으면 받은 줄은 merged 가 지키지만 **방금 열린 minigame3 의 [받기]가 사라진다**(이 가드만 막는 자리 — Swift
        // staleFetchAfterClaimIsDropped 의 team2).
        val settled = edit(claimTodo3) { top ->
            top["missions"] = JsonArray(top.getValue("missions").jsonArray.map { m ->
                val o = m.jsonObject
                if (o.getValue("key").jsonPrimitive.content != "minigame3") m
                else JsonObject(o + mapOf("achieved" to JsonPrimitive(true), "progress" to o.getValue("target"), "achieved_at_ms" to JsonPrimitive(1789620000000L)))
            })
        }
        val gate = CompletableDeferred<Unit>()
        var statusCalls = 0
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> { statusCalls += 1; if (statusCalls == 1) MeReply.Json(status) else MeReply.Gate(gate, MeReply.Json(status)) }
                "achievement_claim" -> MeReply.Json(settled)
                "shop_state" -> MeReply.Json(shop(140))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()
        assertEquals(120L, h.ruby.rubyBalance)
        assertTrue(h.store.achievements!!.missions.first { it.key == "todo3" }.isClaimable)

        h.store.retryAchievements() // 받기 전에 떠난다(문에서 멈춘다)
        runCurrent()
        h.store.claimAchievement("todo3")
        runCurrent()
        assertEquals(140L, h.ruby.rubyBalance, "받기 응답의 잔량")
        assertTrue(h.store.achievements!!.missions.first { it.key == "minigame3" }.isClaimable, "받기 응답이 연 [받기]")
        gate.complete(Unit) // 받기 전의 서버를 말하는 답이 이제 온다
        runCurrent()

        val missions = h.store.achievements!!.missions
        assertTrue(missions.first { it.key == "todo3" }.claimed, "받은 줄에 [받기]가 되살아나지 않는다")
        assertTrue(missions.first { it.key == "minigame3" }.isClaimable, "받기 전 조회가 방금 열린 [받기]를 거두지 않는다")
        assertEquals(4, h.store.achievementClaimableCount, "poke10 · poke50 · streak14 · minigame3")
        assertEquals(140L, h.ruby.rubyBalance, "받기 전 조회의 잔량(120)으로 되돌리지 않는다")
        assertEquals(20L, h.store.claimBurst("todo3")?.amount, "이 호출이 넣은 지급만큼 연출")
        assertEquals(emptySet(), h.store.achievementClaimsInFlight)
        assertEquals(0, h.server.count("shop_state"), "잔량을 옮겼으니 상점을 다시 읽을 까닭이 없다")
        // 버린 조회 때문에 '낡음'이 남지 않는다 — 받기 응답이 신선도 도장을 찍었다(스로틀 안 재조회 0).
        h.store.refreshAchievementsIfStale()
        runCurrent()
        assertEquals(2, statusCalls, "버린 조회 뒤 스로틀 안인데 또 물었다")
        h.assertClean()
    }

    @Test
    fun shopStateThatLeftBeforeTheClaimDoesNotUndoTheClaimedRuby() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "achievement_claim" -> MeReply.Json(claimTodo3)
                "shop_state" -> MeReply.Gate(gate, MeReply.Json(shop(120)))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()
        h.store.launch { h.store.loadShop() } // 받기 **전**에 떠난 상점 조회(잔량 120)
        runCurrent()
        h.store.claimAchievement("todo3")
        runCurrent()
        gate.complete(Unit)
        runCurrent()
        assertEquals(140L, h.ruby.rubyBalance, "떠난 뒤 미러에 쓴 적이 있으면 상점 조회의 잔량은 버린다(1055 → 1000 사고)")
        assertTrue(h.store.shopState.hasLoaded, "상점의 나머지는 옮긴다")
        h.assertClean()
    }

    @Test
    fun weeklyStatusDoesNotRollBackAMirrorWriteMadeWhileItWasInFlight() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "weekly_work_status" -> MeReply.Gate(gate, MeReply.Json(weeklyStatus))
                else -> null
            }
        }
        h.signIn()
        h.store.refreshWeeklyWorkIfStale()
        runCurrent()
        // 조회가 떠 있는 사이 다른 갈래(뽑기 −50 등)가 미러에 썼다 — 값이 마침 같아도(ABA) 횟수로 가른다.
        h.ruby.rubyBalance = 120
        h.ruby.rubyBalance = 70
        gate.complete(Unit)
        runCurrent()
        assertEquals(70L, h.ruby.rubyBalance, "응답의 잔량(120)이 더 새 값을 되돌리지 않는다")
        assertNotNull(h.store.weeklyWork, "상태는 옮긴다")
        assertEquals(0, h.server.count("shop_state"), "받은 것이 없으면 상점을 다시 읽지 않는다")
        h.assertClean()
    }

    @Test
    fun weeklyClaimRereadsTheShopWhenItCouldNotWriteTheRubyAndDropsTheStaleStatus() = runTest {
        val claimGate = CompletableDeferred<Unit>()
        val statusGate = CompletableDeferred<Unit>()
        var statusCalls = 0
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "weekly_work_status" -> { statusCalls += 1; if (statusCalls == 1) MeReply.Json(weeklyStatus) else MeReply.Gate(statusGate, MeReply.Json(weeklyStatus)) }
                "weekly_work_claim" -> MeReply.Gate(claimGate, MeReply.Json(weeklyClaim))
                "shop_state" -> MeReply.Json(shop(190))
                else -> null
            }
        }
        h.signIn()
        h.store.refreshWeeklyWorkIfStale()
        runCurrent()
        assertTrue(h.store.canClaimWeeklyWork)
        assertEquals(70L, h.store.weeklyClaimableRuby)
        h.store.weeklyWorkDidChange() // 받기 전에 떠난 조회(문에서 멈춘다)
        runCurrent()
        h.store.claimWeeklyWork()
        h.store.claimWeeklyWork() // 두 번 눌러도 요청 하나
        runCurrent()
        h.ruby.rubyBalance = 100 // 받기가 떠 있는 사이 다른 쓰기
        claimGate.complete(Unit)
        runCurrent()
        statusGate.complete(Unit)
        runCurrent()

        assertEquals(1, h.server.count("weekly_work_claim"))
        assertEquals(1, h.server.count("shop_state"), "잔량을 못 썼는데 받은 게 있다 → 상점을 다시 읽어 맞춘다")
        assertEquals(190L, h.ruby.rubyBalance)
        assertFalse(h.store.weeklyWork!!.hasClaimable, "받기 전 조회(받을 것 70)가 받기 응답을 덮지 않는다")
        assertEquals(70L, h.store.weeklyClaimBurst?.amount)
        assertFalse(h.store.weeklyClaimInFlight)
        h.assertClean()
    }

    @Test
    fun overlappingClaimsAnsweredOutOfOrderNeverUnclaimARow() = runTest {
        val single = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "achievement_claim" -> if (bodyKey(r.bodyText) == "\"todo3\"") MeReply.Gate(single, MeReply.Json(claimTodo3)) else MeReply.Json(claimAll)
                "shop_state" -> MeReply.Json(shop(195))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()
        h.store.claimAchievement("todo3") // 늦게 답한다
        runCurrent()
        assertTrue(h.store.isClaimingAchievement("todo3"))
        h.store.claimAllAchievements() // 먼저 답한다(전부 받음 · 잔량 195)
        runCurrent()
        assertTrue(h.store.achievements!!.missions.first { it.key == "poke10" }.claimed)
        single.complete(Unit) // todo3 응답(poke10 은 아직 안 받은 옛 모양 · 잔량 140)
        runCurrent()
        val missions = h.store.achievements!!.missions
        assertTrue(missions.first { it.key == "poke10" }.claimed, "받음은 되돌아가지 않는다")
        assertTrue(missions.first { it.key == "streak14" }.claimed)
        assertEquals(195L, h.ruby.rubyBalance, "늦은 응답의 잔량(140)은 그 사이 쓰기에 밀린다")
        assertEquals(0, h.store.achievementClaimableCount)
        h.assertClean()
    }

    // 「미션」 묶음(폰 1.0.13)

    @Test
    fun missionsRowStandsWhenEitherGroupHasSomethingAndThePageRefreshesOnlyItsOwnGroups() = runTest {
        var weeklyExists = false
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.missingFunction
                "weekly_work_status" -> if (weeklyExists) MeReply.Json(weeklyStatus) else MeReply.missingFunction
                else -> null
            }
        }
        h.signIn()
        h.store.refreshMissions()
        advanceUntilIdle()
        assertFalse(h.store.showsMissionsRow, "둘 다 없는 서버엔 [미션] 줄이 없다(빈 줄만 남지 않게)")
        assertTrue(h.store.missionsPageIsEmpty)
        assertEquals(0, h.store.missionClaimableCount)
        weeklyExists = true
        h.store.refreshMissions()
        advanceUntilIdle()
        assertTrue(h.store.showsMissionsRow, "주간만 있어도 줄이 선다")
        assertFalse(h.store.missionsPageIsEmpty)
        assertEquals(2, h.store.missionClaimableCount, "배지 = 주간 받을 단계 둘(지난주 40h · 이번 주 20h)")
        assertEquals(setOf("rpc/achievements_status", "rpc/weekly_work_status"), h.meRequests.map { "rpc/${it.rpcName}" }.toSet(),
            "미션 화면은 자기 묶음만 다시 읽는다(머리·상점·기록·리밋 없음)")
        h.assertClean()
    }

    // 일일 미션(v0.3.64)

    @Test
    fun dailyClaimKeepsItsOwnLedgerApartFromTheCumulativeOne() = runTest {
        var dailyFails = true
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "daily_mission_claim" -> if (dailyFails) MeReply.serverDown else MeReply.Json(dailyGomoku)
                "achievement_claim" -> MeReply.Json(claimAll)
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        assertEquals(2, h.store.dailyMissionClaimableCount)
        assertEquals(2 + 4, h.store.missionClaimableCount, "배지 = 일일 2 + 누적 4(주간은 아직 모름)")
        h.store.claimDailyMission("daily_gomoku")
        advanceUntilIdle()
        assertTrue(h.store.dailyMissionClaimDidFail("daily_gomoku"))
        assertFalse(h.store.achievementClaimDidFail("daily_gomoku"))
        h.store.claimAllAchievements() // 누적 전부 받기 성공 — 누적 장부만 비운다
        advanceUntilIdle()
        assertTrue(h.store.dailyMissionClaimDidFail("daily_gomoku"), "누적 성공이 일일 줄의 실패 문장을 지우지 않는다")
        dailyFails = false
        h.store.claimDailyMission("daily_gomoku")
        advanceUntilIdle()
        assertFalse(h.store.dailyMissionClaimDidFail("daily_gomoku"))
        assertEquals(5L, h.store.dailyClaimBurst("daily_gomoku")?.amount)
        assertEquals(""""daily_gomoku"""", bodyKey(h.server.bodies("daily_mission_claim").last()))
        h.assertClean()
    }

    @Test
    fun statusFetchThatLeftBeforeADailyClaimIsDroppedWhenItArrivesAfter() = runTest {
        // Swift MeDailyMissionStoreTests.staleFetchAfterDailyClaimIsDropped — 일일 받기도 누적 받기와 **같은 도장**을 찍는다. 받기 응답에는 서버가
        // 받기 전에 돌린 정산으로 체스 줄이 **새로 열려** 있다. 받기 전에 떠난 조회(체스 미달성)가 그 뒤에 와서 덮으면 받은 오목 줄은 merged 가
        // 지키지만 **방금 열린 체스 [받기]가 사라진다** — 그 자리는 이 도장만 막는다.
        val dailySettled = edit(dailyGomoku) { top ->
            val daily = top.getValue("daily").jsonObject.toMutableMap()
            daily["missions"] = JsonArray(daily.getValue("missions").jsonArray.map { m ->
                val o = m.jsonObject
                if (o.getValue("key").jsonPrimitive.content != "daily_chess") m
                else JsonObject(o + mapOf("achieved" to JsonPrimitive(true), "progress" to JsonPrimitive(1)))
            })
            top["daily"] = JsonObject(daily)
        }
        val gate = CompletableDeferred<Unit>()
        var statusCalls = 0
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> { statusCalls += 1; if (statusCalls == 1) MeReply.Json(status) else MeReply.Gate(gate, MeReply.Json(status)) }
                "daily_mission_claim" -> MeReply.Json(dailySettled)
                "shop_state" -> MeReply.Json(shop(125))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()
        assertEquals(listOf("daily_timing_bar", "daily_gomoku"), h.store.dailyMissionRows!!.filter { it.row.isClaimable }.map { it.key })

        h.store.retryAchievements() // 받기 전에 떠난다(문에서 멈춘다)
        runCurrent()
        h.store.claimDailyMission("daily_gomoku")
        runCurrent()
        assertEquals(listOf("daily_timing_bar", "daily_chess"), h.store.dailyMissionRows!!.filter { it.row.isClaimable }.map { it.key },
            "받기 응답: 오목은 받았고 체스가 새로 열렸다")
        assertEquals(125L, h.ruby.rubyBalance)
        gate.complete(Unit) // 받기 전의 서버를 말하는 답이 이제 온다
        runCurrent()

        val rows = h.store.dailyMissionRows!!
        assertTrue(rows.first { it.key == "daily_gomoku" }.row.claimed, "받은 줄에 [받기]가 되살아나지 않는다")
        assertTrue(rows.first { it.key == "daily_chess" }.row.isClaimable, "받기 전 조회가 방금 열린 일일 [받기]를 거두지 않는다")
        assertEquals(2, h.store.dailyMissionClaimableCount)
        assertEquals(125L, h.ruby.rubyBalance, "받기 전 조회의 잔량(120)으로 되돌리지 않는다")
        assertEquals(5L, h.store.dailyClaimBurst("daily_gomoku")?.amount)
        assertEquals(0, h.server.count("shop_state"), "잔량을 옮겼으니 상점을 다시 읽을 까닭이 없다")
        assertEquals(2, statusCalls)
        h.assertClean()
    }

    @Test
    fun aDoubleTapIsOneRequestAndClaimAllInFlightHoldsSingleClaims() = runTest {
        // Swift MeAchievementClaimTests.doubleTapSendsOneRequest — 같은 키는 한 번에 하나 · 전부 받기가 떠 있으면 낱개 줄도 기다린다(같은 행을 두
        // 요청이 함께 잡지 않게). 그런데 누적 전부 받기는 **일일** 버튼을 막지 않는다(떠 있음도 두 벌 — MeDailyMissionStoreTests:391).
        val single = CompletableDeferred<Unit>()
        val all = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "achievement_claim" -> if (bodyKey(r.bodyText) == "\"todo3\"") MeReply.Gate(single, MeReply.Json(claimTodo3)) else MeReply.Gate(all, MeReply.Json(claimAll))
                "daily_mission_claim" -> MeReply.Json(dailyGomoku)
                "shop_state" -> MeReply.Json(shop(200))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()

        h.store.claimAchievement("todo3")
        runCurrent()
        assertTrue(h.store.isClaimingAchievement("todo3"))
        h.store.claimAchievement("todo3") // 연타
        runCurrent()
        single.complete(Unit)
        runCurrent()
        assertEquals(1, h.server.count("achievement_claim"), "연타로 요청이 두 번 나갔다(두 번 지급 시도)")
        assertEquals(1, h.store.missionClaimBurstSerial)

        h.store.claimAllAchievements()
        runCurrent()
        assertTrue(h.store.isClaimingAchievement("poke10"), "전부 받기가 떠 있는데 낱개 버튼이 살아 있다")
        assertFalse(h.store.isClaimingDailyMission("daily_gomoku"), "누적 전부 받기가 일일 버튼까지 흐렸다")
        h.store.claimAchievement("poke10") // 막힌다
        h.store.claimDailyMission("daily_gomoku") // 막히지 않는다
        runCurrent()
        all.complete(Unit)
        runCurrent()
        assertEquals(listOf("\"todo3\"", "null"), h.server.bodies("achievement_claim").map(::bodyKey), "전부 받기 중에 낱개가 또 나갔다")
        assertEquals(1, h.server.count("daily_mission_claim"), "누적 전부 받기가 떠 있다고 일일 받기가 막혔다")
        assertEquals(0, h.store.achievementClaimableCount)
        assertEquals(emptySet(), h.store.achievementClaimsInFlight)
        h.assertClean()
    }

    @Test
    fun dailyClaimAllInFlightHoldsDailySinglesButNotTheCumulativeButton() = runTest {
        // Swift MeDailyMissionStoreTests.inFlightIsCountedApartFromCumulative — 연타는 요청 하나 · 일일 전부 받기가 떠 있으면 일일 낱개도 기다린다 —
        // 그런데 **누적 버튼은 그대로 살아 있다**.
        val single = CompletableDeferred<Unit>()
        val all = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "daily_mission_claim" -> if (bodyKey(r.bodyText) == "\"daily_gomoku\"") MeReply.Gate(single, MeReply.Json(dailyGomoku))
                    else MeReply.Gate(all, MeReply.Json(MeFixtures.fixture("_me/rpc.daily_mission_claim.json")))
                "achievement_claim" -> MeReply.Json(claimTodo3)
                "shop_state" -> MeReply.Json(shop(150))
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()

        h.store.claimDailyMission("daily_gomoku")
        runCurrent()
        assertTrue(h.store.isClaimingDailyMission("daily_gomoku"))
        assertFalse(h.store.isClaimingAchievement("todo3"), "일일 받기가 누적 버튼을 흐렸다")
        h.store.claimDailyMission("daily_gomoku") // 연타
        runCurrent()
        single.complete(Unit)
        runCurrent()
        assertEquals(1, h.server.count("daily_mission_claim"), "연타로 요청이 두 번 나갔다(두 번 지급 시도)")

        h.store.claimAllDailyMissions()
        runCurrent()
        assertTrue(h.store.isClaimingDailyMission("daily_timing_bar"), "일일 전부 받기가 떠 있는데 낱개 버튼이 살아 있다")
        assertFalse(h.store.isClaimingAchievement("todo3"), "일일 전부 받기가 누적 버튼까지 흐렸다")
        h.store.claimDailyMission("daily_timing_bar") // 막힌다
        h.store.claimAchievement("todo3") // 막히지 않는다
        runCurrent()
        all.complete(Unit)
        runCurrent()
        assertEquals(listOf("\"daily_gomoku\"", "null"), h.server.bodies("daily_mission_claim").map(::bodyKey), "전부 받기 중에 일일 낱개가 또 나갔다")
        assertEquals(1, h.server.count("achievement_claim"), "일일 받기가 떠 있다고 누적 받기가 막혔다")
        assertEquals(0, h.store.dailyMissionClaimableCount)
        assertEquals(emptySet(), h.store.dailyMissionClaimsInFlight)
        h.assertClean()
    }

    @Test
    fun rolledOverDayBlocksYesterdaysClaimAndAsksForTheNewDay() = runTest {
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        assertEquals(2, h.store.dailyMissionClaimableCount)
        // reset_at_ms 1789657200000 = 2026-09-18 00:00 KST — 기준 시각(14:05)에서 10시간 뒤면 자정을 넘긴다.
        advanceTimeBy(10L * 3_600_000)
        val fetchesBefore = h.server.count("achievements_status")
        h.store.claimDailyMission("daily_gomoku")
        assertEquals(0, h.store.dailyMissionClaimableCount, "날을 넘긴 줄은 받을 수에 안 든다")
        assertEquals(1789657200000L, h.store.dailyMissionRolloverNoted, "넘김을 적었다(버튼이 그 자리에서 내려간다)")
        advanceUntilIdle()
        assertEquals(0, h.server.count("daily_mission_claim"), "어제 줄의 받기는 나가지 않는다")
        assertEquals(fetchesBefore + 1, h.server.count("achievements_status"), "반응 없는 버튼 대신 새 날을 묻는다")
        assertTrue(h.store.dailyMissionRows!!.none { it.row.isClaimable })
        h.assertClean()
    }

    @Test
    fun dayRolloverIsJudgedOnTheServerClockNotThePhoneClock() = runTest {
        // 서버 시계가 이 폰보다 2시간 늦다 — 폰 시계로는 자정을 넘겼어도 서버로는 아직 오늘이다.
        val lagging = edit(status) { it["server_now_ms"] = JsonPrimitive(1789621500000L - 2 * 3_600_000) }
        val h = MeHarness(this) { r -> if (r.rpcName == "achievements_status") MeReply.Json(lagging) else null }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        advanceTimeBy(10L * 3_600_000 + 60_000) // 폰 시각 00:06(다음 날) · 서버 추정 22:06
        assertEquals(2, h.store.dailyMissionClaimableCount, "서버 시각으로는 아직 오늘 — [받기]가 남는다")
        assertFalse(h.store.noteDailyMissionRollover())
    }

    @Test
    fun gameResultAsksOncePerGameAndFollowsAnInFlightFetchWithExactlyOneMore() = runTest {
        val gate = CompletableDeferred<Unit>()
        var calls = 0
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> { calls += 1; if (calls == 2) MeReply.Gate(gate, MeReply.Json(status)) else MeReply.Json(status) }
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        runCurrent()
        h.store.refreshAchievementsAfterGameResult("flappy") // 오늘 이미 채웠다
        runCurrent()
        assertEquals(1, calls, "채운 게임 줄은 묻지 않는다")
        h.store.refreshAchievementsAfterGameResult("tetris") // 아직 0/1 — 묻는다(문에서 멈춘다)
        runCurrent()
        assertEquals(2, calls)
        h.store.refreshAchievementsAfterGameResult("chess")
        h.store.refreshAchievementsAfterGameResult("tetris_duel")
        runCurrent()
        assertEquals(2, calls, "떠 있는 조회가 있으면 깃발만 세운다")
        gate.complete(Unit)
        runCurrent()
        assertEquals(3, calls, "그 조회가 끝난 뒤 정확히 한 번 더")
        h.assertClean()
    }

    @Test
    fun serverWithoutDailyMissionsGetsNoGameResultFetches() = runTest {
        val noDaily = edit(status) { it.remove("daily") }
        val h = MeHarness(this) { r -> if (r.rpcName == "achievements_status") MeReply.Json(noDaily) else null }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        assertIs<MeAchievementSection.Loaded>(h.store.achievementSection)
        assertEquals(MeDailyMissionSection.Hidden, h.store.dailyMissionSection)
        repeat(3) { h.store.refreshAchievementsAfterGameResult("tetris") }
        advanceUntilIdle()
        assertEquals(1, h.server.count("achievements_status"), "일일을 모르는 서버엔 판마다 조회가 늘지 않는다")
    }

    @Test
    fun missingDailyClaimFunctionFoldsOnlyTheDailySection() = runTest {
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(status)
                "daily_mission_claim" -> MeReply.missingFunction
                else -> null
            }
        }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        h.store.claimAllDailyMissions()
        advanceUntilIdle()
        assertFalse(h.store.dailyMissionsAvailable)
        assertEquals(MeDailyMissionSection.Hidden, h.store.dailyMissionSection)
        assertIs<MeAchievementSection.Loaded>(h.store.achievementSection, "누적은 그대로")
        assertFalse(h.store.dailyMissionClaimDidFail("daily_gomoku"), "기능이 없는 것을 '받지 못했어요'로 말하지 않는다")
        assertEquals(4, h.store.missionClaimableCount, "배지에서 일일 몫이 빠진다")
    }

    @Test
    fun phoneDoesNotFilterTheCrossyDailyRow() = runTest {
        val crossyRow = Json.parseToJsonElement(
            """{"key":"daily_crossy","game":"crossy","title":"길건너 아잉이 한 판 하기","detail":"","reward":5,"target":1,"progress":0,
               "achieved":false,"claimed":false,"claimed_at_ms":null,"sort":5}""",
        )
        val withCrossy = edit(status) { top ->
            val daily = top.getValue("daily").jsonObject.toMutableMap()
            daily["missions"] = JsonArray(listOf(crossyRow) + daily.getValue("missions").jsonArray)
            top["daily"] = JsonObject(daily)
        }
        val h = MeHarness(this) { r -> if (r.rpcName == "achievements_status") MeReply.Json(withCrossy) else null }
        h.signIn()
        h.store.launch { h.store.loadAchievements() }
        advanceUntilIdle()
        val crossy = h.store.dailyMissionRows!!.firstOrNull { it.game == "crossy" }
        assertNotNull(crossy, "서버가 주면 그대로 선다(Swift 폰도 거르지 않는다)")
        assertEquals("figure.walk", MeDailyMissionRowContent.make(crossy).icon)
    }
}
