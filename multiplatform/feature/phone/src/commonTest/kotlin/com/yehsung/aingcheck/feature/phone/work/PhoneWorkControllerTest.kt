// 원본: Tests/CheckMobileKitTests/NowPhoneWorkTests.swift(시작 · 종료 · 생존 신호 · 함수 없음 · 세대 가드 · 자리비움 안내) ·
//       Sources/CheckMobileKit/Now/NowStorePhoneWork.swift @ 3bd04bd
// G §2-3 W2-f ①: 폰 근무 RPC 본문에 시각 0 — **스토어가 실제로 낸 요청**을 G5 요청 골든(wire/requests — Swift 서비스가 낸 모양)과 대조한다.
// net 층 G5(W1-d)는 서비스 함수만 잰다 — 이 시험은 지금 탭 버튼·생존 신호 경로가 그 함수를 거쳐 같은 본문을 내는지 잰다(c-fold 후속 지적의 폰 근무 몫).
package com.yehsung.aingcheck.feature.phone.work

import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.wire.models.PhoneWorkResponse
import com.yehsung.aingcheck.core.wire.models.PhoneWorkSessionInfo
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
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
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 폰 근무 시나리오 서버: 소속 · 팀 상태(나는 근무 중 · 열린 세션 s-open) · 디렉터리 · 폰 근무 RPC 셋. */
class PhoneWorkServer {
    var start: Reply = Reply.Json("""{"status":"ok","session":{"id":"S-NEW","started_at":"2026-09-17T05:05:00Z","origin":"phone"},"check_after_seconds":9000,"wallet":{"ruby_balance":12}}""")
    var stop: Reply = Reply.Json("""{"status":"ok","session":{"id":"s-open","started_at":"2026-09-17T01:20:00Z","ended_at":"2026-09-17T05:05:00Z","origin":"phone"}}""")
    var touch: Reply = Reply.Json("""{"status":"ok","session":{"id":"s-open","started_at":"2026-09-17T01:20:00Z","origin":"phone"},"check_after_seconds":9000}""")
    var meWorking = true

    fun route(r: RecordedRequest): Reply? {
        r.rpcName?.let { rpc ->
            return when (rpc) {
                "work_phone_start" -> start
                "work_phone_stop" -> stop
                "work_phone_touch" -> touch
                "app_user_directory" -> Reply.Json("[]")
                else -> null
            }
        }
        return when (r.path) {
            "/rest/v1/work_statuses" -> Reply.Json(
                if (meWorking) {
                    """[{"user_id":"${PhoneHarness.ME}","status":"working","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","active_session_id":"S-OPEN","profiles":{"display_name":"나","avatar_url":null}}]"""
                } else {
                    """[{"user_id":"${PhoneHarness.ME}","status":"offWork","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","profiles":{"display_name":"나","avatar_url":null}}]"""
                },
            )
            "/rest/v1/work_sessions" -> Reply.Json(
                if (meWorking && r.query.any { it.second == "is.null" }) {
                    """[{"id":"S-OPEN","user_id":"${PhoneHarness.ME}","started_at":"2026-09-17T01:20:00Z","ended_at":null}]"""
                } else {
                    "[]"
                },
            )
            "/rest/v1/work_status_devices" -> Reply.Json("[]")
            else -> null
        }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneWorkControllerTest {
    private fun TestScope.rig(server: PhoneWorkServer = PhoneWorkServer()): PhoneHarness {
        val h = PhoneHarness(this) { server.route(it) }
        h.signIn()
        h.app.now.refresh()
        advanceUntilIdle()
        h.markRequests()
        return h
    }

    private fun phoneWorkRequests(h: PhoneHarness): List<RecordedRequest> = h.appRequests.filter { it.rpcName?.startsWith("work_phone_") == true }

    /** 골든 한 사례의 요청(메서드 · 경로 · 본문). */
    private fun goldenRequest(id: String): Triple<String, String, JsonElement> {
        val request = Golden.load("wire/requests").case(id)["requests"]!!.jsonArray.single().jsonObject
        return Triple(request["method"]!!.jsonPrimitive.content, request["path"]!!.jsonPrimitive.content, request["body"]!!)
    }

    private fun actual(r: RecordedRequest): Triple<String, String, JsonElement> =
        Triple(r.method, r.path, if (r.bodyText.isEmpty()) JsonObject(emptyMap()) else Json.parseToJsonElement(r.bodyText))

    /** 본문 어디에도 시각·길이 꼴이 없다(키 이름 · 값 모양 둘 다 — 지어낸 시각이 실리면 근무 시간 위조 P0 가 열린다). */
    private fun assertNoTimeInBody(r: RecordedRequest) {
        val body = if (r.bodyText.isEmpty()) JsonObject(emptyMap()) else Json.parseToJsonElement(r.bodyText)
        fun walk(e: JsonElement) {
            when (e) {
                is JsonObject -> e.forEach { (k, v) ->
                    assertFalse(TIME_KEY.containsMatchIn(k), "시각·길이 꼴 키 '$k' 가 ${r.rpcName} 본문에 있다: ${r.bodyText}")
                    walk(v)
                }
                is JsonArray -> e.forEach(::walk)
                is JsonPrimitive -> {
                    assertFalse(e.isString && ISO_TIME.containsMatchIn(e.content), "시각 글자가 ${r.rpcName} 본문에 있다: ${r.bodyText}")
                    assertFalse(!e.isString && e.content.toDoubleOrNull()?.let { it > 1_000_000_000 } == true, "epoch 꼴 수가 ${r.rpcName} 본문에 있다: ${r.bodyText}")
                }
            }
        }
        walk(body)
    }

    @Test
    fun startStopTouchBodiesMatchG5GoldenAndCarryNoTime() = runTest {
        val h = rig()
        val work = h.app.work
        // 시작: 서버가 세션을 연다 — 본문 {} (골든 startPhoneWork).
        work.clockIn()
        advanceUntilIdle()
        // 생존 신호: 앱이 앞으로 왔다 — 본문 {} (골든 touchPhoneWork). 시작이 방금 스로틀 시각을 찍었으니 61초 뒤에.
        h.clockShift += 61.0
        work.appDidBecomeActive()
        advanceUntilIdle()
        // 종료: 보던 세션 id 하나(소문자 — 골든 stopPhoneWork 의 키 집합). 팀 상태가 대문자 S-OPEN 을 실어 와도 소문자로 나간다.
        work.clockOut()
        advanceUntilIdle()

        val sent = phoneWorkRequests(h)
        assertEquals(listOf("work_phone_start", "work_phone_touch", "work_phone_stop"), sent.map { it.rpcName })
        assertEquals(goldenRequest("startPhoneWork"), actual(sent[0]), "시작 본문이 Swift 골든과 다르다")
        assertEquals(goldenRequest("touchPhoneWork"), actual(sent[1]), "생존 신호 본문이 Swift 골든과 다르다")
        val (gMethod, gPath, gBody) = goldenRequest("stopPhoneWork")
        val (aMethod, aPath, aBody) = actual(sent[2])
        assertEquals(gMethod to gPath, aMethod to aPath)
        assertEquals(gBody.jsonObject.keys, aBody.jsonObject.keys, "종료 본문 키 집합이 골든과 다르다")
        assertEquals("s-open", aBody.jsonObject["p_session_id"]!!.jsonPrimitive.content)
        sent.forEach(::assertNoTimeInBody)
        h.assertClean()
    }

    @Test
    fun clockInAppliesOutcomeWalletAndReloadsWidgetsAfterRefresh() = runTest {
        val h = rig()
        val reloadsBefore = h.widgetReloads
        h.app.work.clockIn()
        advanceUntilIdle()
        val now = h.app.now
        assertEquals(NowText.workStarted, now.workNotice)
        assertEquals("s-new", now.phoneSession?.id, "세션 id 는 소문자로")
        assertEquals(NowWorkOrigin.phone, now.phoneSession?.origin)
        assertEquals(9000, now.phoneSession?.checkAfterSeconds)
        assertEquals(12L, h.app.ruby.rubyBalance, "지갑 정산 결과가 루비 칸에 실린다")
        assertFalse(now.isWorkBusy)
        // 시작 뒤 팀 상태를 다시 읽고(GET work_statuses) 위젯을 스로틀 없이 새로고침한다.
        assertTrue(h.appRequests.any { it.path == "/rest/v1/work_statuses" }, "시작 뒤 카드 새로고침")
        assertTrue(h.widgetReloads > reloadsBefore, "시작 뒤 위젯 즉시 새로고침")
    }

    @Test
    fun alreadyWorkingOnMacAndNoTeamNotices() = runTest {
        val server = PhoneWorkServer()
        server.start = Reply.Json("""{"status":"already_working","session":{"id":"m-1","origin":"mac"}}""")
        val h = rig(server)
        h.app.work.clockIn()
        advanceUntilIdle()
        assertEquals(NowText.alreadyWorkingOnMac, h.app.now.workNotice)
        assertEquals(NowWorkOrigin.mac, h.app.now.phoneSession?.origin)
        server.start = Reply.Json("""{"status":"no_team"}""")
        h.app.work.clockIn()
        advanceUntilIdle()
        assertEquals(NowText.workNeedsTeam, h.app.now.workNotice)
        server.start = Reply.Json("""{"status":"weird"}""")
        h.app.work.clockIn()
        advanceUntilIdle()
        assertEquals(NowText.startFailed, h.app.now.workNotice, "모르는 status 는 실패로 — 지어내지 않는다")
    }

    @Test
    fun stopOutcomesMismatchAndAlreadyStopped() = runTest {
        val server = PhoneWorkServer()
        val h = rig(server)
        var weekly = 0
        // 주간 보상 재조회 고리는 조립(PhoneAppModel)이 나 탭에 잇는다 — 여기서는 그 문이 불렸는지만 센다.
        val work = PhoneWorkController(h.app.now, h.app.ruby, weeklyWorkDidChange = { weekly += 1 })
        h.app.now.phoneWork = work
        server.stop = Reply.Json("""{"status":"mismatch"}""")
        work.clockOut()
        advanceUntilIdle()
        assertEquals(NowText.workChanged, h.app.now.workNotice)
        assertEquals(0, weekly)
        server.stop = Reply.Json("""{"status":"not_working"}""")
        work.clockOut()
        advanceUntilIdle()
        assertEquals(NowText.alreadyStopped, h.app.now.workNotice)
        assertNull(h.app.now.phoneSession)
        assertEquals(1, weekly, "근무가 이미 끝나 있어도 이번 주 누적이 확정됐다 — 주간 보상을 다시 읽는다")
    }

    @Test
    fun touchThrottleOneMinuteOnActiveFiveMinutesWhileActive() = runTest {
        val h = rig()
        val work = h.app.work
        work.appDidBecomeActive()
        advanceUntilIdle()
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.count("work_phone_touch"), "1분 안의 두 번째 활성화는 보내지 않는다")
        h.clockShift += 59.0
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.count("work_phone_touch"))
        h.clockShift += 2.0
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, h.count("work_phone_touch"), "60초가 지나면 다시 보낸다")
        // active 동안의 주기 신호는 5분 스로틀.
        h.clockShift += 120.0
        work.periodicTick()
        advanceUntilIdle()
        assertEquals(2, h.count("work_phone_touch"))
        h.clockShift += 181.0
        work.periodicTick()
        advanceUntilIdle()
        assertEquals(3, h.count("work_phone_touch"))
        assertEquals(3, work.phoneTouchCount)
    }

    @Test
    fun workCheckPushForcesTouchEvenWithinThrottle() = runTest {
        val h = rig()
        val work = h.app.work
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.count("work_phone_touch"))
        work.didReceiveWorkCheckPush()
        advanceUntilIdle()
        assertEquals(2, h.count("work_phone_touch"), "근무 확인 알림은 스로틀 없이 바로 신호를 보낸다(앱을 연 것이 답이다)")
        assertTrue(h.appRequests.count { it.path == "/rest/v1/work_statuses" } >= 1, "카드도 다시 읽는다")
    }

    @Test
    fun missingFunctionHidesWorkControlAndStopsSending() = runTest {
        val server = PhoneWorkServer()
        server.touch = Reply.missingFunction
        val h = rig(server)
        val work = h.app.work
        assertTrue(work.showsWorkControl)
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertFalse(h.app.now.phoneWorkAvailable, "함수가 없는 서버(PGRST202)는 이 세대 동안 기능 없음")
        assertFalse(work.showsWorkControl, "버튼을 숨긴다")
        assertNull(h.app.now.workNotice, "생존 신호의 PGRST202 는 조용히 접는다(⑤)")
        val before = h.appRequests.size
        work.clockIn()
        h.clockShift += 3600.0
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(before, h.appRequests.size, "기능이 없으면 시작·생존 신호를 더 내지 않는다")
        // 시작 버튼의 PGRST202 는 안내 한 줄과 함께 기능을 끈다.
        val server2 = PhoneWorkServer().also { it.start = Reply.missingFunction }
        val h2 = rig(server2)
        h2.app.work.clockIn()
        advanceUntilIdle()
        assertEquals(NowText.workUnavailable, h2.app.now.workNotice)
        assertFalse(h2.app.now.phoneWorkAvailable)
    }

    @Test
    fun offlineTouchReleasesThrottleSoNextActivationRetries() = runTest {
        val server = PhoneWorkServer()
        server.touch = Reply.Offline
        val h = rig(server)
        val work = h.app.work
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertNull(work.lastPhoneTouchAt, "닿지 못했다 — 다음 활성화가 바로 다시 보내게 스로틀을 푼다")
        assertTrue(h.app.now.phoneWorkAvailable, "오프라인은 기능 없음이 아니다")
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, h.count("work_phone_touch"))
    }

    @Test
    fun idleCloseNoticeOncePerSessionPerUser() = runTest {
        val server = PhoneWorkServer()
        server.meWorking = false
        server.touch = Reply.Json("""{"status":"not_working","last":{"id":"IDLE-1","ended_at":"2026-09-17T04:00:00Z","reason":"idle","origin":"phone"}}""")
        val h = rig(server)
        val work = h.app.work
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(NowText.idleClosed("13:00"), h.app.now.workNotice, "자리비움 마감 안내(서버 끝 시각 · KST)")
        h.app.now.workNotice = null
        h.clockShift += 61.0
        work.appDidBecomeActive()
        advanceUntilIdle()
        assertNull(h.app.now.workNotice, "같은 세션의 안내는 한 번만")
        assertEquals("idle-1", h.prefs.getString(PhoneWorkController.IDLE_ACK_PREFIX + PhoneHarness.ME))
    }

    @Test
    fun lateResponseAfterSignOutIsDropped() = runTest {
        val server = PhoneWorkServer()
        val gate = CompletableDeferred<Unit>()
        server.start = Reply.Gate(gate, Reply.Json("""{"status":"ok","session":{"id":"LATE","origin":"phone"},"wallet":{"ruby_balance":99}}"""))
        val h = rig(server)
        val job = launch { h.app.work.clockIn() }
        runCurrent()
        h.app.session.expireSession()
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()
        job.join()
        assertNull(h.app.now.phoneSession, "로그아웃 뒤 도착한 응답은 다음 계정에 쓰이지 않는다")
        assertTrue(h.app.ruby.rubyBalance != 99L, "늦은 지갑 값도 버린다")
    }

    @Test
    fun originFoldsEverythingButPhoneToMac() {
        // §8-1 D:675 · §8-7 W2-f: Windows 가 'windows' 를 실어도 새 출처를 만들지 않고 mac 으로 접는다(옛 iOS 와 같은 판정).
        assertEquals(NowWorkOrigin.phone, PhoneWorkController.originOf("phone"))
        assertEquals(NowWorkOrigin.mac, PhoneWorkController.originOf("mac"))
        assertEquals(NowWorkOrigin.mac, PhoneWorkController.originOf("windows"))
        assertEquals(NowWorkOrigin.mac, PhoneWorkController.originOf("unknown"))
        assertEquals(NowWorkOrigin.mac, PhoneWorkController.originOf(null))
        assertEquals(NowWorkOrigin.mac, PhoneWorkController.originOf("Phone"), "대소문자를 접지 않는다(Swift rawValue 그대로)")
        val response = PhoneWorkResponse(status = "ok", checkAt = "2026-09-17T07:35:00.250Z")
        assertNull(PhoneWorkController.phoneSession(PhoneWorkSessionInfo(id = ""), response), "빈 id 는 세션이 아니다")
        val parsed = PhoneWorkController.phoneSession(PhoneWorkSessionInfo(id = "AB", origin = "windows"), response)!!
        assertEquals("ab", parsed.id)
        assertEquals(NowWorkOrigin.mac, parsed.origin)
        assertEquals(1_789_630_500.25, parsed.checkAt!!.timeIntervalSince1970, "소수초 timestamptz 를 읽는다")
    }

    private companion object {
        val TIME_KEY = Regex("(?i)(_at$|time|date|seconds|duration|minutes|hours|^p_(started|ended|now|ts))")
        val ISO_TIME = Regex("""\d{4}-\d{2}-\d{2}T\d{2}:\d{2}""")
    }
}
