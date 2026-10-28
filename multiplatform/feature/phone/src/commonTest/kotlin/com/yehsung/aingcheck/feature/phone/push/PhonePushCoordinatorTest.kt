// 원본: Tests/CheckMobileKitTests/PushCoordinatorTests.swift(권한 · 등록 · 설명 시트 7일 · 설정 저장 직렬 · 배지 앎 · 포그라운드 표시 · 수락) ·
//       Sources/CheckMobileKit/Push/PushCoordinator.swift @ 3bd04bd
// G §2-3 W2-f ④ 등록은 register_device_fcm 하나 · 알림 권한이 꺼지면 unregister_device 뒤 토큰 없이 재등록 / ⑤ 서버 준비 안 됨은 조용히 접기 —
// 진짜 세션 스토어(W2-a)를 조립째 붙여 **스텁이 받은 요청 순서**로 잰다.
package com.yehsung.aingcheck.feature.phone.push

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhonePushCoordinatorTest {
    private val token = "fcm:" + "A".repeat(40) + "-Bb_9"

    private fun TestScope.rig(
        status: PhonePushAuthorization = PhonePushAuthorization.authorized,
        appConfig: AppConfig = AppConfig(),
        route: (RecordedRequest) -> Reply? = { null },
    ): PhoneHarness {
        val h = PhoneHarness(this, appConfig = appConfig) { r ->
            route(r) ?: when (r.rpcName) {
                "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
                "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
                "gomoku_inbox", "gomoku_lobby", "chess_lobby", "tetris_lobby" -> Reply.missingFunction
                "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
                else -> null
            }
        }
        h.pushSystem.status = status
        h.app.push.attach(h.pushSystem)
        h.signIn()
        return h
    }

    private fun fcmBodies(h: PhoneHarness) = h.server.requests.filter { it.rpcName == "register_device_fcm" }.map { Json.parseToJsonElement(it.bodyText).jsonObject }

    @Test
    fun tokenGoesThroughRegisterDeviceFcmOnlyWithK5Keys() = runTest {
        val h = rig()
        assertEquals(1, h.pushSystem.count("register"), "받을 수 있으면 로그인 직후 토큰을 받으러 간다(실행마다 한 번)")
        h.app.push.didReceivePushToken(token)
        advanceUntilIdle()
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.pushSystem.count("register"), "같은 실행에서 다시 받지 않는다")
        val bodies = fcmBodies(h)
        assertEquals(token, bodies.last()["p_fcm_token"]!!.jsonPrimitive.content, "토큰은 대소문자를 바꾸지 않고 그대로")
        assertEquals(setOf("p_installation_id", "p_app_build", "p_app_version", "p_fcm_token"), bodies.last().keys, "K5 인자 넷")
        assertEquals(PhoneHarness.INSTALLATION, bodies.last()["p_installation_id"]!!.jsonPrimitive.content)
        assertEquals(0, h.server.requests.count { it.rpcName == "register_device" }, "register_device 를 따로 부르지 않는다(§8-1 대체 표)")
        h.assertClean()
    }

    @Test
    fun permissionTurnedOffUnregistersThenReRegistersWithoutToken() = runTest {
        val h = rig()
        h.app.push.didReceivePushToken(token)
        advanceUntilIdle()
        h.markRequests()
        // 사용자가 시스템 설정에서 알림을 껐다 → 다음 활성화가 읽는다.
        h.pushSystem.status = PhonePushAuthorization.denied
        h.app.push.appDidEnterBackground()
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        val device = h.appRequests.filter { it.rpcName == "unregister_device" || it.rpcName?.startsWith("register_device") == true }
        assertEquals(listOf("unregister_device", "register_device_fcm"), device.map { it.rpcName }, "K5: 토큰을 지울 때는 unregister_device 뒤 재등록")
        val reRegister = Json.parseToJsonElement(device[1].bodyText).jsonObject
        assertFalse("p_fcm_token" in reRegister, "재등록은 토큰 없이(키를 뺀다 — null 은 서버가 '유지'로 읽는다)")
        assertNull(h.app.session.pushToken)
        // 꺼진 동안 FCM 이 토큰을 돌려도 올리지 않는다.
        h.markRequests()
        h.app.push.didReceivePushToken("$token-rotated")
        advanceUntilIdle()
        assertEquals(emptyList(), h.rpcNames().filter { it.contains("device") }, "권한이 꺼진 동안 회전된 토큰을 올리지 않는다")
        // 다시 켜면 토큰을 받으러 가고, 받은 토큰을 올린다.
        h.pushSystem.status = PhonePushAuthorization.authorized
        h.app.push.refreshAuthorization()
        advanceUntilIdle()
        assertEquals(2, h.pushSystem.count("register"))
        h.app.push.didReceivePushToken("$token-rotated")
        advanceUntilIdle()
        assertEquals("$token-rotated", fcmBodies(h).last()["p_fcm_token"]!!.jsonPrimitive.content)
        assertEquals(0, h.server.requests.count { it.rpcName == "register_device" })
    }

    @Test
    fun notDeterminedNeverUploadsAndDoesNotTouchDevices() = runTest {
        val h = rig(status = PhonePushAuthorization.notDetermined)
        assertEquals(0, h.pushSystem.count("register"), "미결정이면 토큰을 받지 않는다")
        h.app.push.didReceivePushToken(token)
        advanceUntilIdle()
        assertTrue(fcmBodies(h).none { "p_fcm_token" in it })
        assertEquals(0, h.server.requests.count { it.rpcName == "unregister_device" }, "올린 토큰이 없으면 지울 것도 없다")
    }

    @Test
    fun serverNotReadyAnswersAreFoldedQuietlyAndRetriedNextForeground() = runTest {
        // ⑤ invalid · PGRST202 · unknown_platform — 화면 경고 없이 접고, 다음 포그라운드가 다시 시도한다.
        for (reply in listOf(Reply.Json("""{"status":"invalid"}"""), Reply.missingFunction)) {
            val h = rig { r ->
                when (r.rpcName) {
                    "client_release" -> Reply.Json("""{"status":"unknown_platform"}""")
                    "register_device_fcm" -> reply
                    else -> null
                }
            }
            assertEquals(SessionPhase.SignedIn, h.app.session.phase, "client_release 가 unknown_platform 이어도 막지 않는다")
            assertNull(h.app.session.notice)
            assertNull(h.app.session.pushPrefs, "등록이 서지 않았으니 알림 설정을 모른다")
            assertFalse(h.app.push.knowsPrefs, "모르면 토글을 잠근다(전부 켜짐으로 덮어쓰지 않게)")
            assertFalse(h.app.push.setPreference(PhonePushKind.message, false))
            val before = h.server.requests.count { it.rpcName == "register_device_fcm" }
            h.app.push.didReceivePushToken(token)
            advanceUntilIdle()
            h.app.session.appDidBecomeActive()
            advanceUntilIdle()
            assertTrue(h.server.requests.count { it.rpcName == "register_device_fcm" } > before, "스탬프를 찍지 않았으니 다시 시도한다")
            assertNull(h.app.session.notice, "${(reply as? Reply.Json)?.body}: 경고 없이")
            assertEquals(0, h.server.requests.count { it.rpcName == "set_push_prefs" })
        }
    }

    @Test
    fun primerShowsOnceThenRestsSevenDays() = runTest {
        val h = rig(status = PhonePushAuthorization.notDetermined)
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertTrue(h.app.push.isPrimerPresented)
        assertEquals(1, h.pushSystem.count("presentPrimer"))
        h.app.push.primerLater()
        assertFalse(h.app.push.isPrimerPresented)
        h.app.push.appDidEnterBackground()
        h.clockShift += 6 * 24 * 3600.0
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.pushSystem.count("presentPrimer"), "'나중에'에서 7일 안에는 다시 묻지 않는다")
        h.app.push.appDidEnterBackground()
        h.clockShift += 24 * 3600.0 + 1
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(2, h.pushSystem.count("presentPrimer"), "7일이 지나면 다시")
        // "알림 켜기" → 권한 창 → 허락이면 토큰을 받으러 간다.
        h.app.push.primerAllow()
        advanceUntilIdle()
        assertEquals(1, h.pushSystem.count("requestAuthorization"))
        assertEquals(PhonePushAuthorization.authorized, h.app.push.authorization)
        assertEquals(1, h.pushSystem.count("register"))
    }

    @Test
    fun formSignInWaitsForCredentialSaveGraceBeforePrimer() = runTest {
        val h = PhoneHarness(this)
        h.pushSystem.status = PhonePushAuthorization.notDetermined
        val grace = CompletableDeferred<Unit>()
        h.app.push.credentialPromptGraceSleep = { grace.await() }
        h.app.push.attach(h.pushSystem)
        h.app.start()
        advanceUntilIdle()
        h.app.push.appDidBecomeActive()
        h.tokenReply = Reply.Json("""{"access_token":"${h.jwt(PhoneHarness.ME, "form")}","refresh_token":"r1","user":{"id":"${PhoneHarness.ME}"}}""")
        h.app.session.signIn("me@example.invalid", "pw")
        advanceUntilIdle()
        assertTrue(h.app.session.signedInViaForm)
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(PhonePushCoordinator.PrimerDeferral.credentialPromptGrace, h.app.push.primerDeferralState, "폼 로그인 직후에는 저장 창 유예를 먼저")
        assertEquals(0, h.pushSystem.count("presentPrimer"))
        grace.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, h.pushSystem.count("presentPrimer"), "유예가 창 없이 끝나면 띄운다")
    }

    @Test
    fun prefsSavesAreSerialAndLatestValueWins() = runTest {
        val first = CompletableDeferred<Unit>()
        var saves = 0
        val h = rig { r ->
            if (r.rpcName == "set_push_prefs") {
                saves += 1
                val prefs = Json.parseToJsonElement(r.bodyText).jsonObject["p_prefs"]!!.toString()
                val ok = Reply.Json("""{"status":"ok","push_prefs":$prefs}""")
                if (saves == 1) Reply.Gate(first, ok) else ok
            } else {
                null
            }
        }
        assertTrue(h.app.push.knowsPrefs, "등록 응답이 알림 설정을 알려 줬다")
        val a = async { h.app.push.setPreference(PhonePushKind.message, false) }
        runCurrent()
        val b = async { h.app.push.setPreference(PhonePushKind.gomokuInvite, false) }
        val c = async { h.app.push.setPreference(PhonePushKind.feedbackReply, false) }
        runCurrent()
        assertEquals(1, saves, "도는 저장이 있으면 겹쳐 보내지 않는다")
        assertTrue(h.app.push.isSavingPrefs)
        assertEquals(PushPrefs(message = false, gomokuInvite = false, feedbackReply = false), h.app.push.prefs, "저장 중에는 누른 값을 먼저 보인다")
        first.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf(true, true, true), listOf(a.await(), b.await(), c.await()))
        assertEquals(2, saves, "끝난 뒤 최신 값으로 한 번만 더")
        val last = h.server.requests.last { it.rpcName == "set_push_prefs" }
        assertEquals("""{"message":false,"gomoku_invite":false,"feedback_reply":false}""", Json.parseToJsonElement(last.bodyText).jsonObject["p_prefs"].toString())
        assertFalse(h.app.push.isSavingPrefs)
        assertEquals(PushPrefs(false, false, false), h.app.session.pushPrefs)
        // 끌 수 없는 종류(근무 확인)·Android 체스 신청은 설정을 바꾸지 않는다.
        assertEquals(h.app.push.prefs, PhonePushKind.workCheck.setting(true, h.app.push.prefs))
        assertTrue(PhonePushKind.workCheck.isEnabled(h.app.push.prefs))
        assertEquals(listOf(PhonePushKind.message, PhonePushKind.gomokuInvite, PhonePushKind.feedbackReply), PhonePushKind.configurable)
    }

    @Test
    fun prefsNotFoundWaitsForRegistrationThenRetriesOnce() = runTest {
        var saves = 0
        val h = rig { r ->
            if (r.rpcName == "set_push_prefs") {
                saves += 1
                if (saves == 1) Reply.Json("""{"status":"not_found"}""") else Reply.Json("""{"status":"ok","push_prefs":{"message":false,"gomoku_invite":true,"feedback_reply":true}}""")
            } else {
                null
            }
        }
        h.markRequests()
        assertTrue(h.app.push.setPreference(PhonePushKind.message, false))
        advanceUntilIdle()
        assertEquals(listOf("set_push_prefs", "register_device_fcm", "set_push_prefs"), h.rpcNames(), "기기 행이 없으면 등록을 끝까지 기다린 뒤 한 번 더")
    }

    @Test
    fun badgeIsUnknownUntilServerAnswersAndZeroOnSignOut() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = rig { r -> if (r.rpcName == "message_unread_summary") Reply.Gate(gate, Reply.missingFunction) else null }
        h.app.push.badgeTotalSource = { 4 }
        h.app.push.appDidBecomeActive()
        runCurrent()
        assertEquals(PhonePushCoordinator.BadgeKnowledge.unknown, h.app.push.badgeState)
        assertTrue(h.pushSystem.badges.isEmpty(), "서버 값을 모르면 아이콘을 건드리지 않는다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(PhonePushCoordinator.BadgeKnowledge.stores, h.app.push.badgeState, "요약 함수가 없는 서버(PGRST202)도 '답했다'로 접는다")
        assertEquals(4, h.pushSystem.badges.last())
        h.app.session.signOut()
        advanceUntilIdle()
        assertEquals(0, h.pushSystem.badges.last(), "로그아웃의 0 은 확정값")
        assertTrue(h.pushSystem.calls.containsAll(listOf("removeAll", "unregister")), "앞 계정 알림을 지우고 토큰을 버린다")
    }

    @Test
    fun foregroundArrivalRefreshesStoresAndHidesVisibleConversationAndWorkCheck() = runTest {
        val h = rig()
        h.app.messages.appDidBecomeActive()
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        h.markRequests()
        h.app.router.visibleConversationPeerID = "PEER-1"
        assertEquals(PhonePushPresentation.hidden, h.app.push.didReceive(PhonePushContent.Message("peer-1")), "보고 있는 대화의 메시지는 숨긴다")
        assertEquals(PhonePushPresentation.banner, h.app.push.didReceive(PhonePushContent.Message("peer-2")))
        assertEquals(PhonePushPresentation.hidden, h.app.push.didReceive(PhonePushContent.WorkCheck("s-1")), "앞에 있으면 근무 확인 배너는 숨긴다 — 앱을 연 것이 답")
        assertEquals(PhonePushPresentation.banner, h.app.push.didReceive(PhonePushContent.ChessInvite("m-9")))
        assertEquals(PhonePushPresentation.banner, h.app.push.didReceive(null), "모르는 알림은 그대로 보인다")
        advanceUntilIdle()
        val names = h.rpcNames()
        assertTrue("message_unread_summary" in names, "메시지 알림은 메시지 탭 조회로")
        assertTrue("work_phone_touch" in names, "근무 확인은 생존 신호를 바로")
        assertTrue(names.any { it.startsWith("chess_") }, "체스 신청은 체스 재조회로(받은함이 없다)")
        h.app.push.appDidEnterBackground()
        h.markRequests()
        assertEquals(PhonePushPresentation.banner, h.app.push.didReceive(PhonePushContent.WorkCheck("s-1")), "뒤에 있으면 근무 확인을 보인다")
        assertEquals(PhonePushPresentation.banner, h.app.push.didReceive(PhonePushContent.Message("peer-1")))
        advanceUntilIdle()
        assertEquals(emptyList(), h.rpcNames(), "뒤에서 온 알림은 네트워크를 쓰지 않는다(FCM 짧은 실행 창 — 재조회는 앞으로 올 때)")
    }

    @Test
    fun acceptRespectsDuelsFlagAndOpensInviteOrMatch() = runTest {
        // 깃발이 꺼진 빌드(§8-17 #1)는 수락 RPC 를 내지 않고 그 신청 화면을 연다.
        val locked = rig()
        locked.markRequests()
        locked.app.push.handleResponse(PhonePushContent.GomokuInvite("m-1"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(0, locked.count("gomoku_respond"))
        assertEquals(PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite("m-1")), locked.app.router.lastOpenedTarget)
        // 켜진 빌드는 respond(accept) 를 내고, 판이 안 열렸으면(not_pending) 그 신청으로.
        val open = rig(appConfig = AppConfig(duelsEnabled = true)) { r ->
            if (r.rpcName == "gomoku_respond" || r.rpcName == "chess_respond") Reply.Json("""{"status":"not_pending"}""") else null
        }
        open.markRequests()
        open.app.push.handleResponse(PhonePushContent.GomokuInvite("M-2".lowercase()), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        val respond = open.appRequests.single { it.rpcName == "gomoku_respond" }
        assertEquals("true", Json.parseToJsonElement(respond.bodyText).jsonObject["p_accept"]!!.jsonPrimitive.content)
        assertEquals(PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite("m-2")), open.app.router.lastOpenedTarget)
        open.app.push.handleResponse(PhonePushContent.ChessInvite("c-3"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(1, open.count("chess_respond"), "Android 는 체스 신청도 [수락] 한다")
        assertEquals(PhoneRouteTarget.ChessInvite("c-3"), open.app.router.lastOpenedTarget)
        // 탭은 그 화면을 연다 · 지우기는 아무것도 안 한다.
        open.app.push.handleResponse(PhonePushContent.FeedbackReply(null), PhonePushAction.dismiss)
        assertEquals(PhoneRouteTarget.ChessInvite("c-3"), open.app.router.lastOpenedTarget)
        open.app.push.handleResponse(PhonePushContent.Message("p-1"), PhonePushAction.open)
        assertEquals(PhoneRouteTarget.Message("p-1"), open.app.router.lastOpenedTarget)
    }
}
