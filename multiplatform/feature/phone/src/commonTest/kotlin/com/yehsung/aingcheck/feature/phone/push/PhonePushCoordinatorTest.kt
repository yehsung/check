// 원본: Tests/CheckMobileKitTests/PushCoordinatorTests.swift(권한 · 등록 · 설명 시트 7일 · 설정 저장 직렬 · 배지 앎 · 포그라운드 표시 · 수락) ·
//       Tests/CheckMobileKitTests/PushBadgeTests.swift(아이콘 = 메시지 + 게임) · Tests/CheckMobileKitTests/PushTestSupport.swift:306-311(respondAcceptOK) ·
//       Sources/CheckMobileKit/Push/PushCoordinator.swift @ 3bd04bd
// G §2-3 W2-f ④ 등록은 register_device_fcm 하나 · 알림 권한이 꺼지면 unregister_device 뒤 토큰 없이 재등록 / ⑤ 서버 준비 안 됨은 조용히 접기 —
// 진짜 세션 스토어(W2-a)를 조립째 붙여 **스텁이 받은 요청 순서**로 잰다.
package com.yehsung.aingcheck.feature.phone.push

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.stores.me.missionClaimableCount
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.routing.PhoneNavRequest
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.testkit.golden.Golden
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

    @Test
    fun acceptThatOpensTheMatchGoesToTheMatchNotTheInvite() = runTest {
        // Swift gomokuAccept: gomoku_respond 가 판을 열면(ok + state) 대국으로. 기준선(위 시험): not_pending 이면 그 신청으로.
        val h = rig(appConfig = AppConfig(duelsEnabled = true)) { r ->
            when (r.rpcName) {
                "gomoku_respond" -> Reply.Json(respondAcceptOK(MATCH))
                "gomoku_state" -> Reply.Json("""{"status":"not_found"}""")
                else -> null
            }
        }
        h.markRequests()
        h.app.push.handleResponse(PhonePushContent.GomokuInvite(MATCH), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(1, h.count("gomoku_respond"))
        assertEquals(MATCH, h.app.gomoku.match?.id?.lowercase(), "전제: 수락 응답이 판을 열었다")
        assertEquals(PhoneRouteTarget.Games(GamesRouteRequest.GomokuMatch(MATCH)), h.app.router.lastOpenedTarget, "판이 열렸으면 신청이 아니라 대국으로")
        assertEquals(95L, h.app.ruby.rubyBalance, "수락 응답의 잔액이 루비 칸 하나에")
    }

    // ---------------------------------------------------------------- 딥링크 대상 해석(W2-f 검증 7차 지적: 조정자가 라우터를 바로 불렀다)

    /** 게임 RPC 는 전부 오프라인(판 상태는 시험이 로비 응답으로 심는다). */
    private fun TestScope.gameRig(appConfig: AppConfig = AppConfig(duelsEnabled = true)): PhoneHarness {
        val h = PhoneHarness(this, appConfig = appConfig) { r ->
            val name = r.rpcName ?: return@PhoneHarness null
            if (name.startsWith("chess_") || name.startsWith("gomoku_") || name.startsWith("tetris_")) Reply.Offline else null
        }
        h.signIn()
        return h
    }

    private suspend fun PhoneHarness.liveChess() {
        app.chess.applyLobby(SwiftJson.decode(ChessLobbyResponse.serializer(), """{"status":"ok","me":{"active_match_id":"C-1"}}"""))
        scope.advanceUntilIdle()
        assertTrue(app.games.hasLiveChessMatch, "시험 조립: 체스 판이 흐른다")
    }

    private suspend fun PhoneHarness.liveTetris() {
        app.tetris.applyLobby(SwiftJson.decode(TetrisLobbyResponse.serializer(), """{"status":"ok","me":{"active_match_id":"T-1"}}"""))
        scope.advanceUntilIdle()
        assertTrue(app.games.hasLiveTetrisMatch, "시험 조립: 테트리스 판이 흐른다")
    }

    private suspend fun PhoneHarness.liveGomoku() {
        app.gomoku.applyLobby(SwiftJson.decode(GomokuLobbyResponse.serializer(), """{"status":"ok","me":{"active_match_id":"G-1"}}"""))
        assertTrue(app.games.hasLiveGomokuMatch, "시험 조립: 오목 판이 흐른다")
    }

    private val gamesRoot = listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Games(GamesRouteRequest.Games)))

    @Test
    fun notificationTapsFollowTheSameRulesAsDeepLinks() = runTest {
        // 기준선(다른 입력): 판이 없으면 오목 신청 알림 탭은 그 신청 화면을 연다.
        val idle = gameRig()
        idle.app.router.drainRequests()
        idle.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.open)
        advanceUntilIdle()
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Games(GamesRouteRequest.GomokuInvite("g-1")))), idle.app.router.drainRequests())
        // 체스 판 중 오목 신청 알림 탭 → 게임 탭 첫 화면(GamesStore.routeStep — Swift 는 GamesTab.consumePendingRoute 가 막는다).
        val chess = gameRig().apply { liveChess() }
        chess.app.router.drainRequests()
        chess.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.open)
        advanceUntilIdle()
        assertEquals(gamesRoot, chess.app.router.drainRequests(), "체스 판 중 오목 신청 화면을 열었다")
        // 테트리스 판 중(D5 — 판돈을 잃는 길)도 같다.
        val tetris = gameRig().apply { liveTetris() }
        tetris.app.router.drainRequests()
        tetris.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.open)
        advanceUntilIdle()
        assertEquals(gamesRoot, tetris.app.router.drainRequests(), "테트리스 판 중 오목 신청 화면을 열었다")
        // 오목 판 중 체스 신청 알림 탭 → 게임 탭 첫 화면(chessEntryBlock — Android 만).
        val gomoku = gameRig().apply { liveGomoku() }
        gomoku.app.router.drainRequests()
        gomoku.app.push.handleResponse(PhonePushContent.ChessInvite("c-1"), PhonePushAction.open)
        advanceUntilIdle()
        assertEquals(gamesRoot, gomoku.app.router.drainRequests(), "오목 판 중 체스 신청 화면을 열었다")
        // 제보 답장 알림 탭 → 나 탭 뿌리 + 제보 화면 + 그 제보에 초점(Swift MeTab.consumePendingRoute → MeStore.open).
        val me = gameRig()
        me.app.router.drainRequests()
        me.app.push.handleResponse(PhonePushContent.FeedbackReply("r-1"), PhonePushAction.open)
        advanceUntilIdle()
        assertEquals(
            listOf(PhoneNavRequest.Open(PhoneRouteTarget.Me(MeRoute.Me)), PhoneNavRequest.PushMe(MeDestination.Feedback)),
            me.app.router.drainRequests(),
        )
        assertEquals("r-1", me.app.me.focusedReportID, "제보 답장 알림이 그 제보에 초점을 두지 않았다")
    }

    @Test
    fun acceptWhileAnotherDuelIsLiveSendsNoRespondAndLandsOnGamesRoot() = runTest {
        // 기준선(다른 입력): 깃발 켬 · 판 없음 → 수락 RPC 1건.
        val idle = gameRig()
        idle.markRequests()
        idle.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(1, idle.count("gomoku_respond"))
        // 깃발 켬 · 테트리스 판 중 [수락] → 수락 RPC 0(서버 오목 게이트는 테트리스를 모른다 — D5) · 게임 탭 첫 화면.
        val tetris = gameRig().apply { liveTetris() }
        tetris.markRequests()
        tetris.app.router.drainRequests()
        tetris.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(0, tetris.count("gomoku_respond"), "테트리스 판 중 오목 수락을 냈다")
        assertEquals(gamesRoot, tetris.app.router.drainRequests())
        // 깃발 꺼짐(내부 트랙) · 테트리스 판 중 → 수락 RPC 는 원래 0 이고, 대체 길(신청 화면 열기)도 같은 규칙을 지난다.
        val locked = gameRig(AppConfig()).apply { liveTetris() }
        locked.markRequests()
        locked.app.router.drainRequests()
        locked.app.push.handleResponse(PhonePushContent.GomokuInvite("g-1"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(0, locked.count("gomoku_respond"))
        assertEquals(gamesRoot, locked.app.router.drainRequests(), "깃발 꺼짐의 대체 길이 규칙을 건너뛰었다")
        // 깃발 켬 · 오목 판 중 체스 [수락] → chess_respond 0 · 게임 탭 첫 화면.
        val gomoku = gameRig().apply { liveGomoku() }
        gomoku.markRequests()
        gomoku.app.router.drainRequests()
        gomoku.app.push.handleResponse(PhonePushContent.ChessInvite("c-1"), PhonePushAction.acceptInvite)
        advanceUntilIdle()
        assertEquals(0, gomoku.count("chess_respond"), "오목 판 중 체스 수락을 냈다")
        assertEquals(gamesRoot, gomoku.app.router.drainRequests())
    }

    // ---------------------------------------------------------------- 앱 아이콘 배지 원천(조정자의 기본 배선 — 덮어쓰지 않는다)

    @Test
    fun appIconCountsMessagesAndGamesButNotMissionsThroughTheDefaultSource() = runTest {
        val achievements = Golden.load("missions/achievements").case("fixture-_me/rpc.achievements_status.json")["json"]!!.jsonPrimitive.content
        val h = rig { r ->
            when (r.rpcName) {
                "message_unread_summary" -> Reply.Json("""{"status":"ok","total":3,"peers":[{"peer_user_id":"p-1","count":3}]}""")
                "achievements_status" -> Reply.Json(achievements)
                else -> null
            }
        }
        h.app.me.appDidBecomeActive()
        h.app.messages.appDidBecomeActive()
        advanceUntilIdle()
        val missions = h.app.me.missionClaimableCount
        assertTrue(missions > 0, "전제: 받을 보상이 있어야 '미션을 안 더한다'를 잰다 — $missions")
        assertEquals(3, h.app.badges.messages)
        h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(PhonePushCoordinator.BadgeKnowledge.stores, h.app.push.badgeState)
        assertEquals(3, h.pushSystem.badges.last(), "아이콘 = 메시지 3 + 게임 0 (받을 보상 $missions 은 탭 막대만)")
    }

    @Test
    fun signOutForgetsTheStoredPushToken() = runTest {
        val h = rig()
        h.app.push.didReceivePushToken(token)
        advanceUntilIdle()
        assertEquals(token, h.app.session.pushToken, "전제: 받은 토큰을 세션이 들고 있다")
        h.app.session.signOut()
        advanceUntilIdle()
        assertNull(h.app.session.pushToken, "로그아웃은 저장된 FCM 토큰을 잊는다(다음 계정이 앞 사람 토큰으로 등록하지 않게)")
        assertNull(h.prefs.getString(SessionPrefsKeys.pushToken))
    }

    private companion object {
        const val MATCH = "e4444444-5555-4666-8777-000000000004"
        const val PEER = "b2222222-3333-4444-8555-000000000002"

        /** Swift `PushHarness.respondAcceptOK` 와 같은 모양(판이 열린 수락 응답). */
        fun respondAcceptOK(match: String): String {
            val row = """{"id":"$match","turn":"black","black":"${PhoneHarness.ME}","board":"${".".repeat(225)}","stake":5,"white":"$PEER","result":null,""" +
                """"status":"active","winner":null,"opponent":"${PhoneHarness.ME}","challenger":"$PEER","end_reason":null,"move_count":0,""" +
                """"deadline_ms":1789621530000,"finished_ms":null,"turn_started_ms":1789621500000,"invite_expires_ms":1789621560000}"""
            val opponent = """{"user_id":"$PEER","character":"aing","avatar_url":null,"display_name":"하늘"}"""
            val state = """{"match":$row,"moves":[],"my_color":"black","opponent":$opponent,"ruby_balance":95,"server_now_ms":1789621500000,""" +
                """"my_auto_streak":0,"opponent_auto_streak":0}"""
            return """{"status":"ok","accepted":true,"state":$state,"ruby_balance":95,"server_now_ms":1789621500000}"""
        }
    }
}
