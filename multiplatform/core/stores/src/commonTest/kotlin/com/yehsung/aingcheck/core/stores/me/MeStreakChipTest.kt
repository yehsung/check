// 원본: Tests/CheckMobileKitTests/V1017StreakChipTests.swift @ 1ca907fa (decoding · notFromCappedProgress · merging · copy · wiring · oldServerHides · goneServerAndResetHide)
//
// 값은 `achievements_status` 응답의 새 최상위 키 `streak_days`(서버 초안 — 저장소 밖, 적용 전). 키가 있을 때만 칩을 그려서 서버와 폰의 출시 순서가 자유롭다.
// 미션 줄의 `progress` 로 대신하면 안 된다: target 에서 잘리고 달성 뒤 target 에 고정이라 30일을 넘긴 사람은 2일째여도 30 이다.
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.achievements.HeaderStreakCopy
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeStreakChipTest {
    /** 옛 서버의 진짜 응답 모양(데모 픽스처) — 키가 없다. */
    // 데모 픽스처는 1.0.16 이후 `streak_days` 를 싣는다(맥 · 폰 main — 폰 V1016StreakChipTests 도 픽스처가 아니라 키 없는 본문을 쓴다).
    // 그래서 '옛 서버'는 픽스처에서 그 키를 **뺀** 본문이다 — 나머지 칸은 데모 그대로.
    private val oldServer = JsonObject(
        (Json.parseToJsonElement(MeFixtures.fixture("_me/rpc.achievements_status.json")) as JsonObject).filterKeys { it != "streak_days" },
    ).toString()

    private fun withStreak(value: String, base: String = oldServer): String =
        base.trimEnd().dropLast(1) + ""","streak_days":$value}"""

    private fun decode(json: String): AchievementStatus = AchievementStatus.decode(Json.parseToJsonElement(json))

    // MARK: 디코드

    @Test
    fun theFixtureIsReallyAnOldServerResponse() {
        // 없으면: 픽스처에 키가 생기는 날 아래 '옛 서버' 시험들이 뜻 없이 초록이다.
        assertFalse("streak_days" in (Json.parseToJsonElement(oldServer) as JsonObject).keys)
    }

    @Test
    fun decodingKeepsTheValueAndAMissingOrBrokenKeyIsNull() {
        assertEquals(3L, decode(withStreak("3")).streakDays)
        assertEquals(0L, decode(withStreak("0")).streakDays, "0일은 값이다(칩을 그린다)")
        val missing = decode(oldServer)
        assertNull(missing.streakDays, "키가 없는 서버에서 값을 지어냈다")
        assertTrue(missing.missions.isNotEmpty())
        assertNull(decode(withStreak("null")).streakDays)
        val garbage = decode(withStreak("""{"a":1}"""))
        assertNull(garbage.streakDays)
        assertEquals(missing.missions, garbage.missions, "칸 하나 때문에 응답을 잃었다")
        assertEquals(missing.daily, garbage.daily, "칸 하나 때문에 일일 미션을 잃었다")
    }

    @Test
    fun aCappedMissionProgressIsNotTheStreak() {
        val body = """{"missions":[
            {"key":"streak14","series":"streak","tier":1,"title":"연속 14일","target":14,"progress":14,"claimed":true},
            {"key":"streak30","series":"streak","tier":2,"title":"연속 30일","target":30,"progress":30,"claimed":true}
        ],"streak_days":2}"""
        val status = decode(body)
        assertEquals(30L, status.missions.first { it.key == "streak30" }.progress, "대조: 줄의 값은 target 고정이다")
        assertEquals(2L, status.streakDays)
    }

    @Test
    fun mergingFollowsTheNewResponseAndAMissingKeyHides() {
        val previous = decode(withStreak("5"))
        assertEquals(6L, decode(withStreak("6")).merged(previous).streakDays)
        assertNull(decode(oldServer).merged(previous).streakDays, "옛 값을 붙들고 있다")
        // 받은 줄 되돌림 방지 길(claimedBefore 가 찬 갈래)에서도 같다 — 픽스처에는 받은 줄이 있다.
        assertTrue(previous.missions.any { it.claimed }, "대조: 되돌림 방지 갈래를 지나야 한다")
        assertEquals(1L, decode(withStreak("1")).merged(previous).streakDays)
    }

    // MARK: 문구

    @Test
    fun copyMatchesThePhoneSentenceToTheLetter() {
        assertEquals("연속 3일 근무!", HeaderStreakCopy.text(3))
        assertEquals("연속 0일 근무!", HeaderStreakCopy.text(0))
        assertEquals("연속 0일 근무!", HeaderStreakCopy.text(-2))
        assertEquals("연속 3일 근무", HeaderStreakCopy.accessibilityLabel(3))
        assertEquals("flame.fill", HeaderStreakCopy.icon)
    }

    // MARK: 스토어

    @Test
    fun activeAppFetchReachesTheStoreWithoutOpeningTheTabAndAClaimUpdatesIt() = runTest {
        var statusReply = withStreak("4")
        val h = MeHarness(this) { r ->
            when (r.rpcName) {
                "achievements_status" -> MeReply.Json(statusReply)
                "achievement_claim" -> MeReply.Json(withStreak("5", MeFixtures.fixture("_me/rpc.achievement_claim@todo3.json")))
                else -> MeReply.missingFunction
            }
        }
        h.signIn()
        runCurrent()
        assertNull(h.store.streakDays, "받기 전에 값을 그렸다")

        h.store.appDidBecomeActive()
        advanceUntilIdle()
        assertFalse(h.store.isTabVisible)
        assertEquals(4L, h.store.streakDays, "나 탭을 안 열면 칩이 안 선다")
        assertEquals(1, h.server.count("achievements_status"), "칩 때문에 조회가 늘었다")

        h.store.claimAchievement("todo3")
        advanceUntilIdle()
        assertEquals(5L, h.store.streakDays, "받기 응답도 값을 옮긴다")
        h.assertClean()
    }

    @Test
    fun anOldServerHidesTheChipAndKeepsTheMissions() = runTest {
        val h = MeHarness(this) { r -> if (r.rpcName == "achievements_status") MeReply.Json(oldServer) else null }
        h.signIn()
        h.store.loadAchievements()
        advanceUntilIdle()
        assertTrue(h.store.achievements != null)
        assertNull(h.store.streakDays, "키가 없는데 값을 지어냈다(잘린 progress 를 읽었나)")
        assertTrue(h.store.achievementRows.isNotEmpty())
        h.assertClean()
    }

    @Test
    fun aGoneServerAndSignOutDropTheValue() = runTest {
        var gone = false
        val h = MeHarness(this) { r ->
            if (r.rpcName == "achievements_status") (if (gone) MeReply.missingFunction else MeReply.Json(withStreak("4"))) else null
        }
        h.signIn()
        h.store.loadAchievements()
        advanceUntilIdle()
        assertEquals(4L, h.store.streakDays)
        h.store.reset()
        assertNull(h.store.streakDays, "앞 계정의 연속 일수가 남았다")

        h.store.loadAchievements()
        advanceUntilIdle()
        assertEquals(4L, h.store.streakDays)
        gone = true
        h.store.loadAchievements()
        advanceUntilIdle()
        assertNull(h.store.streakDays, "이 서버엔 기능이 없는데 칩이 남았다")
        h.assertClean()
    }

    @Test
    fun aFailedFetchKeepsTheLastKnownValue() = runTest {
        // Swift 시험에 없는 자리: 받아 둔 값이 있으면 실패해도 미션 줄을 그대로 그린다 — 칩만 깜빡이면 안 된다.
        var down = false
        val h = MeHarness(this) { r ->
            if (r.rpcName == "achievements_status") (if (down) MeReply.serverDown else MeReply.Json(withStreak("4"))) else null
        }
        h.signIn()
        h.store.loadAchievements()
        advanceUntilIdle()
        down = true
        h.store.loadAchievements()
        advanceUntilIdle()
        assertTrue(h.store.achievementsState.hasFailed, "대조: 실패 갈래를 지났다")
        assertEquals(4L, h.store.streakDays)
        h.assertClean()
    }
}
