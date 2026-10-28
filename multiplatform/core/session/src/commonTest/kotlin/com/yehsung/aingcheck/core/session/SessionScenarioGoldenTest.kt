// 원본: Tests/CheckMobileKitTests/GoldenExport/session/GoldenExportSession.swift(G7 세션 시나리오 — 생성기) @ 1b8260d
// G §2-3 W2-a ⑧: C-X9 가 정한 조건(본문 정규화 + 순서 없는 모음)으로 Swift 세션 스토어의 시나리오 여섯 판을 Kotlin 세션 스토어가 재생해
// 같은 요청 모음 · 같은 끝 상태를 내는지 대조한다. 플랫폼 접기(spec.normalization)는 생성기와 같은 규칙이다.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.net.fetchMyInviteCode
import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.jwtExpired
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.session.signout.SignOutCleanupLedger
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SessionScenarioGoldenTest {
    private val golden = Golden.load("session/scenarios")

    /** 한 판의 재료: 하네스 + 자리표시(토큰 → 이름). */
    private class Run(val h: SessionHarness, tokens: List<Pair<String, String>>) {
        val placeholders: List<Pair<String, String>> = tokens + listOf(StubServer.STUB_ANON to "<ANON>")
        fun scrub(text: String): String = placeholders.fold(text) { acc, (raw, name) -> acc.replace(raw, name) }
    }

    private fun TestScope.run(tokens: List<Pair<String, String>>, route: (RecordedRequest) -> Reply?): Run {
        val h = SessionHarness(this, route = route)
        h.store.clientReleaseTimeoutMillis = 0 // 생성기와 같다: 상한 없음
        return Run(h, tokens)
    }

    /** 생성기 `normalized(_:_:)` 와 같은 규칙. */
    private fun normalized(r: RecordedRequest, run: Run): JsonObject {
        var path = r.path
        val text = run.scrub(r.bodyText)
        val body: JsonElement = if (text.isEmpty()) {
            JsonNull
        } else {
            when (val parsed = SwiftJson.parse(text)) {
                is JsonObject -> {
                    val members = parsed.toMutableMap()
                    if (r.rpcName == "register_device_fcm" || r.rpcName == "register_device") {
                        path = "/rest/v1/rpc/<device-registration>"
                        members.remove("p_platform")
                    }
                    if (r.rpcName == "client_release" && "p_platform" in members) members["p_platform"] = JsonPrimitive("<PLATFORM>")
                    JsonObject(members)
                }
                else -> parsed
            }
        }
        return JsonObject(
            mapOf(
                "method" to JsonPrimitive(r.method),
                "path" to JsonPrimitive(path),
                "query" to JsonArray(r.query.map { (k, v) -> JsonArray(listOf(JsonPrimitive(k), JsonPrimitive(run.scrub(v)))) }),
                "authorization" to JsonPrimitive(run.scrub(r.authorization)),
                "body" to body,
            ),
        )
    }

    private fun phaseName(phase: SessionPhase): String = when (phase) {
        SessionPhase.Launching -> "launching"
        is SessionPhase.NeedsUpdate -> "needsUpdate:${phase.minBuild}"
        SessionPhase.SignedOut -> "signedOut"
        SessionPhase.SignedIn -> "signedIn"
        SessionPhase.AnotherInstanceRunning -> "anotherInstanceRunning"
    }

    private fun str(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

    private fun endState(run: Run, extra: Map<String, JsonElement> = emptyMap()): JsonObject {
        val h = run.h
        val s = h.store
        return JsonObject(
            mapOf(
                "phase" to JsonPrimitive(phaseName(s.phase)),
                "generation" to JsonPrimitive(s.generation),
                "access" to str(h.vaultAccess?.let(run::scrub)),
                "refresh" to str(h.vaultRefresh?.let(run::scrub)),
                "email" to str(s.storedEmail),
                "notice" to str(s.notice),
                "teamName" to str(s.profile?.teamName),
                "ledger" to JsonPrimitive(SignOutCleanupLedger.load(h.vault).size),
                "refreshCalls" to JsonPrimitive(
                    h.server.requests.count { it.path == "/auth/v1/token" && it.queryValue("grant_type") == "refresh_token" },
                ),
            ) + extra,
        )
    }

    /** 순서 없는 비교: 양쪽을 정규 글자로 바꿔 코드포인트 순서로 정렬한다(생성기와 같은 정렬 기준). */
    private fun sortedTexts(items: List<JsonElement>): List<String> = items.map { GoldenCanonical.text(it) }.sortedWith(::codePointCompare)

    private fun codePointCompare(a: String, b: String): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val ca = codePointAt(a, i)
            val cb = codePointAt(b, j)
            if (ca.first != cb.first) return ca.first.compareTo(cb.first)
            i += ca.second
            j += cb.second
        }
        return (a.length - i).compareTo(b.length - j)
    }

    private fun codePointAt(s: String, i: Int): Pair<Int, Int> {
        val c = s[i]
        if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
            return (((c.code - 0xD800) shl 10) + (s[i + 1].code - 0xDC00) + 0x10000) to 2
        }
        return c.code to 1
    }

    private fun check(caseID: String, run: Run, end: JsonObject) {
        val expected = golden.case(caseID)
        val actualRequests = run.h.server.requests.map { normalized(it, run) }
        assertEquals(
            sortedTexts(expected.array("requests")),
            sortedTexts(actualRequests),
            golden.failure(caseID, "요청 모음이 Swift 와 다르다"),
        )
        assertEquals(expected.obj("end"), end, golden.failure(caseID, "끝 상태가 Swift 와 다르다"))
        assertEquals(emptyList(), run.h.server.unrouted.map { it.key }, golden.failure(caseID, "경로 없는 요청"))
    }

    @Test
    fun launchRefresh401RetrySignOut() = runTest {
        val old = SessionFixtures.jwt(SessionClock0.at(20.0), salt = "old")
        val fresh1 = SessionFixtures.jwt(SessionClock0.at(3600.0), salt = "fresh1")
        val fresh2 = SessionFixtures.jwt(SessionClock0.at(7200.0), salt = "fresh2")
        var refreshes = 0
        val run = run(listOf(old to "<OLD>", fresh1 to "<FRESH1>", fresh2 to "<FRESH2>")) { r ->
            when {
                r.path == "/auth/v1/token" -> { refreshes += 1; if (refreshes == 1) auth(fresh1, "refresh-1") else auth(fresh2, "refresh-2") }
                r.rpcName == "my_team_invite_code" -> if (r.authorization == "Bearer $fresh2") Reply.Json("""[{"invite_code":"ABC123"}]""") else jwtExpired
                r.rpcName == "client_release" -> releaseOK
                r.rpcName == "register_device_fcm" -> registerOK
                r.rpcName == "unregister_device" -> SessionFixtures.unregistered
                r.path == "/rest/v1/memberships" -> membershipOK
                r.path == "/auth/v1/logout" -> SessionFixtures.emptyObject
                else -> null
            }
        }
        val h = run.h
        h.seed(access = old, refresh = "refresh-old")
        h.store.launch()
        advanceUntilIdle()
        val code = h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) }
        val teamBefore = h.store.profile?.teamName
        h.store.signOut()
        advanceUntilIdle()
        check("launch-refresh-401-retry-signout", run, endState(run, mapOf("inviteCode" to str(code), "teamNameBeforeSignOut" to str(teamBefore))))
    }

    @Test
    fun launchRefreshFatal() = runTest {
        val old = SessionFixtures.jwt(SessionClock0.at(20.0), salt = "old")
        val run = run(listOf(old to "<OLD>")) { r ->
            when {
                r.rpcName == "client_release" -> releaseOK
                r.path == "/auth/v1/token" -> SessionFixtures.invalidGrant
                else -> null
            }
        }
        run.h.seed(access = old, refresh = "refresh-old")
        run.h.store.launch()
        advanceUntilIdle()
        check("launch-refresh-fatal", run, endState(run))
    }

    @Test
    fun launchRefreshTransient() = runTest {
        val old = SessionFixtures.jwt(SessionClock0.at(20.0), salt = "old")
        val run = run(listOf(old to "<OLD>")) { r ->
            when {
                r.rpcName == "client_release" -> releaseOK
                r.rpcName == "register_device_fcm" -> registerOK
                r.path == "/auth/v1/token" -> Reply.Json("""{"message":"upstream"}""", 503)
                r.path == "/rest/v1/memberships" -> membershipOK
                else -> null
            }
        }
        run.h.seed(access = old, refresh = "refresh-old")
        run.h.store.launch()
        advanceUntilIdle()
        check("launch-refresh-transient", run, endState(run))
    }

    @Test
    fun signOutExpiredAccessLedgerRefresh() = runTest {
        val run = run(emptyList()) { r ->
            when {
                r.rpcName == "client_release" -> releaseOK
                r.rpcName == "register_device_fcm" -> registerOK
                r.rpcName == "unregister_device" -> if (r.authorization == "Bearer access-0") jwtExpired else SessionFixtures.unregistered
                r.path == "/rest/v1/memberships" -> membershipOK
                r.path == "/auth/v1/token" -> auth("cleanup-access", "cleanup-refresh")
                r.path == "/auth/v1/logout" -> if (r.authorization == "Bearer cleanup-access") SessionFixtures.emptyObject else jwtExpired
                else -> null
            }
        }
        run.h.seed(access = "access-0", refresh = "r0")
        run.h.store.launch()
        advanceUntilIdle()
        run.h.store.signOut()
        advanceUntilIdle()
        check("signout-expired-access-ledger-refresh", run, endState(run))
    }

    @Test
    fun deleteAccountOrder() = runTest {
        val run = run(emptyList()) { r ->
            when {
                r.rpcName == "client_release" -> releaseOK
                r.rpcName == "register_device_fcm" -> registerOK
                r.rpcName == "delete_my_account" -> Reply.Json("null")
                r.path == "/rest/v1/memberships" -> membershipOK
                r.path == "/auth/v1/token" -> auth("reauth-access", "reauth-refresh")
                r.path.startsWith("/storage/v1/object/avatars/") -> SessionFixtures.emptyObject
                else -> null
            }
        }
        run.h.seed(access = "access-0", refresh = "r0")
        run.h.store.launch()
        advanceUntilIdle()
        val outcome = run.h.store.deleteAccount("pw")
        advanceUntilIdle()
        check("delete-account-order", run, endState(run, mapOf("deleted" to JsonPrimitive(outcome == AccountDeletionOutcome.Deleted))))
    }

    @Test
    fun launchBelowMinBuild() = runTest {
        val run = run(emptyList()) { r ->
            if (r.rpcName == "client_release") Reply.Json("""{"status":"ok","platform":"ios","min_build":5,"latest_build":7,"notes":null}""") else null
        }
        run.h.seed(access = "access-0", refresh = "r0")
        run.h.store.launch()
        advanceUntilIdle()
        check("launch-below-min-build", run, endState(run, mapOf("latestBuild" to (run.h.store.latestBuild?.let(::JsonPrimitive) ?: JsonNull))))
    }

    /** 골든의 판이 시험 판과 같은 수인가(새 판이 생기면 이 파일에 재생을 더해야 빨강이 풀린다 — 미소비 판 금지). */
    @Test
    fun everyGoldenCaseIsReplayed() {
        val replayed = setOf(
            "launch-refresh-401-retry-signout", "launch-refresh-fatal", "launch-refresh-transient",
            "signout-expired-access-ledger-refresh", "delete-account-order", "launch-below-min-build",
        )
        val ids = golden.cases.map { (it["id"] as JsonPrimitive).content }.toSet()
        assertEquals(replayed, ids)
        assertTrue(golden.cases.all { it.array("requests").isNotEmpty() }, "빈 시나리오는 '같다'가 공짜로 나온다")
    }

    /** 생성기 시계(2026-09-17 14:05:00 KST 에 멈춤) 기준 시각. 하네스 시계도 가상 시간 0 에서 같은 시각이다. */
    private object SessionClock0 {
        fun at(seconds: Double) = com.yehsung.aingcheck.core.session.app.SessionClock.demoInstant.addingTimeInterval(seconds)
    }
}
