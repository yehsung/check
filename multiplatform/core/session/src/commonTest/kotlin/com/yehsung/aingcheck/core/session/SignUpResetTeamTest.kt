// 원본: Tests/CheckMobileKitTests/BasePasswordResetTests.swift · MobileSignUpStore.swift · MobileTeamJoinForm.swift · NowTeamJoin.swift @ 1b8260d
// C§4 #8(가입 응답에 세션이 없으면 "메일 보냄", identities [] 면 이미 있는 계정) · 팀 칸 한 벌 · 재설정 3단 · 쿨다운.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.session.reset.PasswordResetStore
import com.yehsung.aingcheck.core.session.reset.PasswordResetText
import com.yehsung.aingcheck.core.session.signup.SignUpStore
import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.core.session.team.TeamJoinStore
import com.yehsung.aingcheck.core.wire.codePointCountCompat
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SignUpResetTeamTest {
    private val preview = Reply.Json("""[{"team_id":"team-9","name":"구름팀","weekly_goal_hours":40,"member_count":3}]""")

    private fun base(r: RecordedRequest): Reply? = when {
        r.rpcName == "client_release" -> releaseOK
        r.rpcName == "register_device_fcm" -> registerOK
        r.path == "/rest/v1/memberships" -> membershipOK
        r.rpcName == "lookup_team_by_code" -> preview
        else -> null
    }

    /** 코드 세기: 시험은 UTF-16 대리쌍을 하나로 세면 충분하다(그래핌 판정은 W1-c 골든 몫). */
    private val counter = object : GraphemeCounter {
        override fun count(text: String): Int = text.codePointCountCompat()
    }

    private fun SignUpStore.fill(email: String = "new@b.co", center: String? = "seoul") {
        displayName.value = "구름"
        this.email.value = email
        password.value = "secret1"
        this.center.value = center
    }

    /** #8 ①: 세션 없는 200(가입 확인을 켠 서버) → 코드 화면 · 첫 메일은 다시 보내지 않는다 · 비밀번호는 비운다. */
    @Test
    fun signUpWithoutSessionOpensCodeScreen() = runTest {
        val h = SessionHarness(this) { r ->
            if (r.path == "/auth/v1/signup") Reply.Json("""{"user":{"id":"u-new","identities":[{"id":"i1"}]}}""") else base(r)
        }
        val store = SignUpStore(h.store)
        store.teamCode()
        store.fill()
        store.submit()!!.join()
        assertEquals(SignUpStore.Stage.ConfirmCode, store.stage)
        assertEquals(SignUpText.confirmSent, store.notice)
        assertEquals("", store.password.value)
        assertEquals(0, h.server.count("/auth/v1/resend"), "가입 요청이 첫 메일을 보냈다")
        assertEquals(5, store.resendSeconds, "첫 잠금 5초")
        advanceTimeBy(5_001)
        runCurrent()
        assertEquals(0, store.resendSeconds)
        assertEquals(SessionPhase.Launching, h.store.phase, "세션은 아직 넘기지 않는다")
    }

    /** #8 ②: `identities: []` 인 가짜 사용자 200 = 이미 있는 계정 → "이미 가입된 이메일" · 코드 화면 아님 · 출구 없음(INV 8b6a03d1). */
    @Test
    fun emptyIdentitiesMeansAlreadyRegistered() = runTest {
        val h = SessionHarness(this) { r ->
            if (r.path == "/auth/v1/signup") Reply.Json("""{"user":{"id":"u-fake","identities":[]}}""") else base(r)
        }
        val store = SignUpStore(h.store)
        store.teamCode()
        store.fill()
        store.submit()!!.join()
        assertEquals(SignUpStore.Stage.Account, store.stage)
        assertEquals("이미 가입된 이메일", store.notice)
        assertFalse(store.offersConfirmationExit, "인증된 계정엔 출구를 달지 않는다")
        assertTrue(SignUpStore.offersConfirmationExit("이메일 확인 필요"), "미확인 계정 문구엔 단다(대조)")
    }

    /** 세션이 온 가입 → join_team → 세션 스토어로 넘긴다(로그인과 같은 길: 금고 · 이메일 · 기기 등록). */
    @Test
    fun signUpWithSessionJoinsTeamThenAdopts() = runTest {
        val h = SessionHarness(this) { r ->
            when {
                r.path == "/auth/v1/signup" -> auth("new-access", "new-refresh", "u-new")
                r.rpcName == "join_team" -> Reply.Json("""[{"team_id":"team-9","name":"구름팀","weekly_goal_hours":40}]""")
                else -> base(r)
            }
        }
        val store = SignUpStore(h.store)
        store.teamCode()
        store.fill()
        store.submit()!!.join()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        assertEquals("new-access", h.vaultAccess)
        assertEquals("new@b.co", h.store.storedEmail)
        assertEquals(1, h.server.count("/rest/v1/rpc/register_device_fcm"))
        val signup = h.server.requests.single { it.path == "/auth/v1/signup" }
        assertTrue(signup.bodyText.contains("\"center\":\"seoul\""), "센터는 메타 자리에")
    }

    /** 가드 순서(맥 signUp()): 입력 셋 → 팀 칸(코드 미확인) → 센터. 막히면 요청 0. 센터 미선택은 키보드 제출 경로에서도 막는다. */
    @Test
    fun guardsRunInMacOrderWithoutRequests() = runTest {
        val h = SessionHarness(this) { r -> base(r) }
        val store = SignUpStore(h.store)
        assertNull(store.submit())
        assertEquals(SignUpText.missingFields, store.notice)
        store.fill(center = null)
        assertNull(store.submit())
        assertEquals(SignUpText.codeUnverified, store.notice)
        store.teamCode()
        assertNull(store.submit())
        assertEquals(SignUpText.centerRequired, store.notice)
        assertFalse(store.canSubmit)
        assertEquals(listOf("rpc/lookup_team_by_code"), h.server.paths())
    }

    /** join_team 0행(센터 게이트) → 무소속 · 미리보기 비움 · "다른 센터 팀이에요"(INV d11a3161) · 같은 코드 재제출은 왕복 없이 막힌다. */
    @Test
    fun zeroRowJoinIsCenterGateNotWrongCode() = runTest {
        val h = SessionHarness(this) { r ->
            when {
                r.path == "/auth/v1/signup" -> auth("new-access", "new-refresh", "u-new")
                r.rpcName == "join_team" -> Reply.Json("[]")
                else -> base(r)
            }
        }
        val store = SignUpStore(h.store)
        store.teamCode()
        store.fill()
        store.submit()!!.join()
        assertEquals(SignUpStore.Stage.Teamless, store.stage)
        assertNull(store.teamForm.joinPreview.value)
        assertEquals(SignUpText.teamlessJoinBlocked, store.previewLine?.text)
        assertEquals(false, store.previewLine?.isSuccess)
        val joins = h.server.count("/rest/v1/rpc/join_team")
        assertNull(store.submit(), "같은 코드 재제출은 가드가 막는다")
        assertEquals(joins, h.server.count("/rest/v1/rpc/join_team"))
        assertEquals(SessionPhase.Launching, h.store.phase, "팀이 정해질 때까지 세션을 넘기지 않는다")
    }

    /** 재전송 안내: 출구(첫 발송)는 "보냈어요", 그 뒤는 "앞 코드는 이제 쓸 수 없어요"(INV 9dd2a9a0 · 65f4ca6b). 429 는 서버 초. */
    @Test
    fun resendCopyDistinguishesFirstSendAndRateLimit() = runTest {
        var resend = 0
        val h = SessionHarness(this) { r ->
            if (r.path == "/auth/v1/resend") {
                resend += 1
                if (resend == 3) Reply.Json("""{"msg":"For security purposes, you can only request this after 42 seconds."}""", 429) else SessionFixtures.emptyObject
            } else base(r)
        }
        val store = SignUpStore(h.store)
        store.beginConfirmation(" New@B.co ")
        assertEquals(SignUpText.confirmSent, store.notice)
        assertEquals("new@b.co", store.confirmSentEmail)
        advanceTimeBy(5_001)
        runCurrent()
        store.resendCode()
        assertEquals(SignUpText.confirmResent, store.notice)
        assertEquals(60, store.resendSeconds)
        store.resendCode()
        assertEquals(PasswordResetText.cooldown, store.notice, "잠금 중엔 왕복하지 않는다")
        assertEquals(2, resend)
        advanceTimeBy(60_001)
        runCurrent()
        store.resendCode()
        assertEquals(PasswordResetText.alreadySent, store.notice)
        assertEquals(42, store.resendSeconds, "남은 초는 서버가 진실")
        assertFalse(store.noticeIsError)
    }

    /** 재설정 3단: 코드 발송 → 6자리 검증(왕복 전 거름) → 새 비밀번호 → 로그인 상태로 잇는다. 발송 문구는 계정 유무를 흘리지 않는다. */
    @Test
    fun passwordResetThreeStepsThenSignsIn() = runTest {
        val h = SessionHarness(this) { r ->
            when {
                r.path == "/auth/v1/recover" -> SessionFixtures.emptyObject
                r.path == "/auth/v1/verify" -> auth("recovery-access", "recovery-refresh")
                r.path == "/auth/v1/user" -> SessionFixtures.emptyObject
                else -> base(r)
            }
        }
        val reset = PasswordResetStore(h.store, " A@B.co ", counter)
        reset.requestCode()
        assertEquals(PasswordResetStore.Step.code, reset.step)
        assertEquals(PasswordResetText.sent, reset.message)
        assertTrue(h.server.requests.single { it.path == "/auth/v1/recover" }.bodyText.contains("a@b.co"))
        reset.verifyCode("12-34")
        assertEquals(PasswordResetText.invalidCode, reset.message)
        assertEquals(0, h.server.count("/auth/v1/verify"), "6자리 미만은 왕복 전에 거른다")
        reset.verifyCode("123 456")
        assertEquals(PasswordResetStore.Step.newPassword, reset.step)
        reset.submitNewPassword("short")
        assertEquals(PasswordResetText.shortPassword, reset.message)
        reset.submitNewPassword("longer1")
        advanceUntilIdle()
        assertEquals(PasswordResetStore.Phase.done, reset.phase)
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        assertEquals("recovery-access", h.vaultAccess)
        assertEquals("Bearer recovery-access", h.server.requests.single { it.path == "/auth/v1/user" }.authorization)
    }

    /** '지금' 탭 무소속 카드: 401 이면 세션 갱신 재시도를 거쳐 합류하고 onTeamSettled 를 부른다(역할은 지어내지 않는다 — 다시 읽는 쪽 몫). */
    @Test
    fun teamJoinStoreRetriesThroughSessionAndSettles() = runTest {
        val h = SessionHarness(this) { r ->
            when {
                r.rpcName == "join_team" ->
                    if (r.authorization == "Bearer access-0") SessionFixtures.jwtExpired
                    else Reply.Json("""[{"team_id":"team-9","name":"구름팀","weekly_goal_hours":40}]""")
                r.path == "/auth/v1/token" -> auth("access-1", "r1")
                else -> base(r)
            }
        }
        h.seed(access = "access-0", refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        val team = TeamJoinStore(SessionContext(h.store))
        var settled = 0
        team.onTeamSettled = { settled += 1 }
        assertNull(team.submit())
        assertEquals(SignUpText.codeUnverified, team.notice)
        team.form.teamCode.value = "abc-123"
        team.form.previewTeamCode().join()
        assertEquals("팀 구름팀 · 3명 · 주 40시간", team.previewLine?.text)
        team.submit()!!.join()
        assertEquals(1, settled)
        assertFalse(team.isSubmitting)
        assertEquals(1, h.server.count("/auth/v1/token"), "401 → 조정자 갱신 1회")
        assertTrue(h.server.requests.filter { it.rpcName == "join_team" }.all { it.bodyText.contains("ABC123") }, "코드는 정규화해 싣는다")
    }

    private suspend fun SignUpStore.teamCode() {
        teamForm.teamCode.value = "abc123"
        teamForm.performPreviewTeamCode()
    }
}
