// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift deleteAccount(password:) @ efb3a5f (profile?.email ?? storedEmail + 입력 그대로)
//
// 7차 로컬 앱 e2e: 같은 계정의 재로그인은 200 인데 계정 삭제 화면 재인증은 400 invalid_credentials ×2(한 번은 칸에 17글자).
// 앱 결함인지 가르는 요청 모양 시험 — 폼 로그인과 삭제 재인증은 **같은 엔드포인트**(/auth/v1/token?grant_type=password)에
// **같은 본문**을 보내야 한다: 이메일은 로그인 때 다듬어 저장한 그 글자(대소문자 그대로 · 앞뒤 공백만 뺌), 비밀번호는 입력 그대로(다듬지 않음).
// 이 시험이 초록이면 같은 글자를 친 재인증이 로그인과 다른 답을 받을 길이 앱에는 없다 — 400 은 칸에 들어간 글자(자동 입력) 쪽이다.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class ReauthRequestShapeTest {
    private fun route(r: RecordedRequest): Reply? = when {
        r.path == "/auth/v1/token" && r.queryValue("grant_type") == "password" -> auth("access-1", "r1")
        r.rpcName == "client_release" -> releaseOK
        r.rpcName == "register_device_fcm" -> registerOK
        r.path == "/rest/v1/memberships" -> membershipOK
        r.method == "DELETE" && r.path.startsWith("/storage/v1/object/avatars/") -> SessionFixtures.emptyObject
        r.path.startsWith("/rest/v1/profiles") -> Reply.Json("[]")
        r.rpcName == "delete_my_account" -> Reply.Json("null")
        else -> null
    }

    @Test
    fun reauthSendsTheFormLoginBodyByteForByte() = runTest {
        // 앞뒤 공백·대소문자 섞인 이메일, 앞뒤 공백·기호·한글이 든 비밀번호(17글자) — 어느 쪽이든 다듬기·소문자화가 끼면 본문이 갈린다.
        val typedEmail = "  Rank.Me@Example.Invalid \t"
        val password = " p@ss wörd!한글 x1 "
        assertEquals(17, password.length)
        val h = SessionHarness(this, route = ::route)
        h.store.signIn(typedEmail, password)
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)

        assertEquals(AccountDeletionOutcome.Deleted, h.store.deleteAccount(password))
        advanceUntilIdle()
        val tokens = h.server.requests.filter { it.path == "/auth/v1/token" }
        assertEquals(listOf("password", "password"), tokens.map { it.queryValue("grant_type") }, "둘 다 password grant: $tokens")
        val login = SwiftJson.parse(tokens[0].bodyText) as JsonObject
        val reauth = SwiftJson.parse(tokens[1].bodyText) as JsonObject
        assertEquals(JsonPrimitive("Rank.Me@Example.Invalid"), login["email"], "로그인은 앞뒤 공백만 뺀다(대소문자 그대로)")
        assertEquals(JsonPrimitive(password), login["password"], "비밀번호는 다듬지 않는다")
        assertEquals(login, reauth, "재인증 본문 = 로그인 본문")
        h.assertClean()
    }
}
