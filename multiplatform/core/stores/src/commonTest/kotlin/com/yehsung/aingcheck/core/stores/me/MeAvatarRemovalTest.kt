// 원본: Tests/checkTests/V0336AvatarRemovalTests.swift:174-262(요청 순서 · null 본문 · 파일 남음 판정) · :348-437(결과 문구 · 연타 · 로그인 전) · :438(로그아웃 뒤 늦은 응답) · :469-491(접기) · :575(유무를 묻지 않는 문구) · Sources/check/CheckSettingsView.swift:1147(CenterSettingsRowState)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeAvatarRemovalTest {
    private val storagePath = "/storage/v1/object/avatars/user-1.jpg"
    private val photo = SwiftURL.parse("https://example.com/me.jpg")

    private fun TestScope.harness(storage: MeReply = MeReply.Json("{}"), patch: MeReply = MeReply.Json("", 204)): MeHarness {
        val h = MeHarness(this) { r: RecordedRequest ->
            when {
                r.method == "DELETE" && r.path == storagePath -> storage
                r.method == "PATCH" && r.path == "/rest/v1/profiles" -> patch
                else -> null
            }
        }
        h.signIn()
        return h
    }

    /** ① PATCH 본문에 키가 null 로 실린다(키를 빼면 PostgREST 가 "아무 칸도 안 고침"으로 200) ② 스토리지 DELETE 가 먼저. 머리 값이 비고 결과는 성공. */
    @Test
    fun removalDeletesTheFileFirstThenPatchesNullAndSaysDone() = runTest {
        val h = harness()
        advanceUntilIdle()
        h.store.avatarURL = photo
        h.store.avatarNotice = "프로필 사진 변경됨"
        h.store.beginAvatarRemoval()
        assertTrue(h.store.isConfirmingAvatarRemoval)
        assertTrue(h.store.performAvatarRemoval())
        val calls = h.meRequests.map { "${it.method} ${it.path}" }
        assertEquals(listOf("DELETE $storagePath", "PATCH /rest/v1/profiles"), calls)
        val patch = h.meRequests.last()
        val body = Json.parseToJsonElement(patch.bodyText).jsonObject
        assertEquals(setOf("avatar_url"), body.keys)
        assertEquals(JsonNull, body["avatar_url"], "키를 빼지 않고 null 을 싣는다")
        assertEquals("eq.user-1", patch.query.first { it.first == "id" }.second)
        assertNull(h.store.avatarURL, "표시는 착용 캐릭터로 돌아간다")
        assertNull(h.store.avatarNotice, "옛 '프로필 사진 변경됨'이 남지 않는다")
        assertEquals("기본 캐릭터로 되돌렸어요", h.store.avatarRemovalNotice)
        assertEquals(AvatarRemovalNoticeTone.success, h.store.avatarRemovalNoticeTone)
        assertFalse(h.store.isConfirmingAvatarRemoval)
        assertFalse(h.store.isRemovingAvatar)
        h.assertClean()
    }

    /** ③ 사진을 올린 적 없는 사람(404)도 온전한 성공 — 표는 그대로 비운다. */
    @Test
    fun missingFileIsStillSuccess() = runTest {
        val h = harness(storage = MeReply.Json("""{"error":"not_found"}""", 404))
        advanceUntilIdle()
        assertTrue(h.store.performAvatarRemoval())
        assertEquals(1, h.meRequests.count { it.method == "PATCH" })
        assertEquals("기본 캐릭터로 되돌렸어요", h.store.avatarRemovalNotice)
        h.assertClean()
    }

    /** ③ 파일을 못 지웠으면 표는 비우되 "되돌렸어요"라고 말하지 않는다(공개 버킷의 얼굴). */
    @Test
    fun leftFileClearsTheTableButDoesNotClaimSuccess() = runTest {
        val h = harness(storage = MeReply.Json("""{"error":"forbidden"}""", 403))
        advanceUntilIdle()
        h.store.avatarURL = photo
        assertFalse(h.store.performAvatarRemoval())
        assertEquals(1, h.meRequests.count { it.method == "PATCH" }, "파일이 남아도 표는 비운다")
        assertNull(h.store.avatarURL)
        assertEquals("사진 파일이 아직 남아 있어요. 잠시 후 다시 시도해 주세요", h.store.avatarRemovalNotice)
        assertEquals(AvatarRemovalNoticeTone.warning, h.store.avatarRemovalNoticeTone)
        h.assertClean()
    }

    /** PATCH 가 실패하면 사진은 그대로고 실패를 말한다 · 연타 가드가 풀려 다시 누를 수 있다. */
    @Test
    fun patchFailureKeepsThePhotoAndCanRetry() = runTest {
        val h = harness(patch = MeReply.Json("""{"message":"nope"}""", 500))
        advanceUntilIdle()
        h.store.avatarURL = photo
        assertFalse(h.store.performAvatarRemoval())
        assertEquals(photo, h.store.avatarURL)
        assertEquals(AvatarRemovalNoticeTone.failure, h.store.avatarRemovalNoticeTone)
        assertTrue(!h.store.avatarRemovalNotice.isNullOrEmpty())
        assertFalse(h.store.isRemovingAvatar)
        val before = h.meRequests.size
        h.store.performAvatarRemoval()
        assertTrue(h.meRequests.size > before, "실패 뒤엔 다시 나간다")
        h.assertClean()
    }

    /** 왕복 중에는 두 번째가 안 나간다. */
    @Test
    fun secondTapWhileInFlightSendsNothing() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = harness(storage = MeReply.Gate(gate, MeReply.Json("{}")))
        runCurrent()
        h.storeScope.launch { h.store.performAvatarRemoval() }
        runCurrent()
        assertTrue(h.store.isRemovingAvatar)
        assertFalse(h.store.performAvatarRemoval())
        runCurrent()
        assertEquals(1, h.meRequests.count { it.method == "DELETE" })
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, h.meRequests.count { it.method == "DELETE" })
        assertFalse(h.store.isRemovingAvatar)
    }

    /** 로그인 전: 요청 없이 말한다(조용히 아무 일도 안 하는 버튼을 두지 않는다). */
    @Test
    fun signedOutTapSendsNothingAndSaysWhy() = runTest {
        val h = MeHarness(this) { null }
        assertFalse(h.store.performAvatarRemoval())
        assertEquals(emptyList(), h.server.requests.map { it.key })
        assertEquals("로그인하면 사진을 지울 수 있어요", h.store.avatarRemovalNotice)
        assertEquals(AvatarRemovalNoticeTone.failure, h.store.avatarRemovalNoticeTone)
    }

    /** 로그아웃 뒤 도착한 응답은 다음 계정을 건드리지 않는다. */
    @Test
    fun lateAnswerAfterSignOutDoesNotTouchTheNextAccount() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = harness(storage = MeReply.Gate(gate, MeReply.Json("{}")))
        runCurrent()
        h.storeScope.launch { h.store.performAvatarRemoval() }
        runCurrent()
        h.store.reset()
        h.signIn("user-2")
        runCurrent()
        h.store.avatarURL = photo
        gate.complete(Unit)
        runCurrent()
        assertEquals(photo, h.store.avatarURL, "다음 사람의 사진을 지웠다")
        assertNull(h.store.avatarRemovalNotice)
    }

    /** 떠 있던 머리 GET(지우기 전 사진 주소)이 늦게 와도 사진을 되살리지 않는다. */
    @Test
    fun lateHeaderDoesNotBringThePhotoBack() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = MeHarness(this) { r: RecordedRequest ->
            when {
                r.method == "DELETE" -> MeReply.Json("{}")
                r.method == "PATCH" -> MeReply.Json("", 204)
                r.path == "/rest/v1/profiles" && r.query.any { it.second == "display_name,avatar_url" } ->
                    MeReply.Gate(gate, MeReply.Json("""[{"display_name":"새벽","avatar_url":"https://example.com/me.jpg"}]"""))
                r.path == "/rest/v1/profiles" -> MeReply.Json("[]")
                else -> null
            }
        }
        h.signIn()
        runCurrent()
        h.storeScope.launch { h.store.loadHeader() }
        runCurrent()
        h.store.performAvatarRemoval()
        gate.complete(Unit)
        runCurrent()
        assertNull(h.store.avatarURL)
    }

    /** 확인 단계는 화면을 넘어 살아남지 않는다 — 다시 열면 평상. 결과 줄도 접힌다. 로그아웃도 접는다. */
    @Test
    fun confirmationAndResultFoldWhenTheScreenOpensOrCloses() = runTest {
        val h = MeHarness(this) { r -> if (r.path == "/rest/v1/profiles") MeReply.Json("[]") else null }
        h.signIn()
        advanceUntilIdle()
        h.store.beginAvatarRemoval()
        h.store.profileDidDisappear()
        assertFalse(h.store.isConfirmingAvatarRemoval, "닫을 때")
        h.store.beginAvatarRemoval()
        h.store.profileDidAppear()
        assertFalse(h.store.isConfirmingAvatarRemoval, "열 때")
        h.store.avatarRemovalNotice = "기본 캐릭터로 되돌렸어요"
        h.store.profileDidDisappear()
        assertNull(h.store.avatarRemovalNotice)
        h.store.beginAvatarRemoval()
        h.store.reset()
        assertFalse(h.store.isConfirmingAvatarRemoval, "로그아웃")
    }

    /** 누르는 순간 앞선 결과 줄을 치운다 — 새 확인 위에 옛 "되돌렸어요"가 남지 않게. */
    @Test
    fun beginningClearsTheOldResult() = runTest {
        val h = MeHarness(this) { null }
        h.store.avatarRemovalNotice = "기본 캐릭터로 되돌렸어요"
        h.store.beginAvatarRemoval()
        assertNull(h.store.avatarRemovalNotice)
    }

    /** 한 줄 우선순위: 결과 > 로그인 전 > 확인 > 기본. 문구는 사진 유무를 묻지 않는다. */
    @Test
    fun noticePriorityAndWording() {
        assertEquals("X", AvatarRemovalText.notice("X", signedIn = false, confirming = true))
        assertEquals("로그인하면 사진을 지울 수 있어요", AvatarRemovalText.notice(null, signedIn = false, confirming = true))
        assertEquals("지운 사진은 되돌릴 수 없어요. 다시 쓰려면 새로 올려야 해요.", AvatarRemovalText.notice(null, signedIn = true, confirming = true))
        assertEquals("지우면 내 자리에 착용한 캐릭터가 대신 보여요.", AvatarRemovalText.notice(null, signedIn = true, confirming = false))
        assertEquals("기본 캐릭터로 되돌리기", AvatarRemovalText.action)
        assertEquals("되돌리기", AvatarRemovalText.confirm)
        assertEquals("취소", AvatarRemovalText.cancel)
        assertEquals("지우는 중…", AvatarRemovalText.inFlight)
        assertEquals("사진을 지우지 못했어요", AvatarRemovalText.failureMessage)
        assertFalse("사진이 있으면" in AvatarRemovalText.detail)
    }

    // ---------------------------------------------------------------- 소속 센터 행

    @Test
    fun centerRowStates() {
        val loading = CenterSettingsRowState.of(loaded = false, center = "seoul")
        assertIs<CenterSettingsRowState.Loading>(loading)
        assertEquals("…", loading.value)
        assertEquals("불러오는 중…", loading.caption)
        val unset = CenterSettingsRowState.of(loaded = true, center = null)
        assertEquals("미지정", unset.value)
        assertEquals("가입할 때 안 골랐어요. 운영자에게 말해 주세요.", unset.caption)
        assertEquals(CenterSettingsRowState.Unset, CenterSettingsRowState.of(loaded = true, center = "marsbase"), "모르는 서버값은 미지정으로 접는다")
        val chosen = CenterSettingsRowState.of(loaded = true, center = "busan")
        assertEquals("부산", chosen.value)
        assertEquals("이름 옆에 배지로 보여요. 바꾸려면 운영자에게.", chosen.caption)
        assertEquals("서울", CenterSettingsRowState.of(loaded = true, center = "seoul").value)
    }

    /** 센터 GET 만 실패하면 "미지정"으로 단정하지 않는다. 행이 다시 묻고, 받은 뒤엔 왕복이 없다. */
    @Test
    fun centerFailureStaysLoadingThenRecoversOnce() = runTest {
        var centerOK = false
        var centerCalls = 0
        val h = MeHarness(this) { r: RecordedRequest ->
            when {
                r.path == "/rest/v1/profiles" && r.query.any { it.second == "center" } -> {
                    centerCalls += 1
                    if (centerOK) MeReply.Json("""[{"center":"seoul"}]""") else MeReply.Json("""{"message":"down"}""", 500)
                }
                r.path == "/rest/v1/profiles" -> MeReply.Json("""[{"display_name":"새벽","avatar_url":null}]""")
                else -> null
            }
        }
        h.signIn()
        advanceUntilIdle()
        h.store.loadHeader()
        assertFalse(h.store.centerLoaded)
        assertIs<CenterSettingsRowState.Loading>(CenterSettingsRowState.of(h.store.centerLoaded, h.store.centerServerValue))
        centerOK = true
        h.store.loadMyCenterIfNeeded()
        assertEquals("서울", CenterSettingsRowState.of(h.store.centerLoaded, h.store.centerServerValue).value)
        val after = centerCalls
        h.store.loadMyCenterIfNeeded()
        assertEquals(after, centerCalls, "이미 알면 왕복이 없다")
        h.store.reset()
        assertFalse(h.store.centerLoaded, "로그아웃 뒤 앞 사람 센터를 안다고 하지 않는다")
    }

    @Test
    fun termsRowPointsAtTheAppLinksAddress() {
        assertEquals("이용약관", MeText.termsOfService)
        assertEquals("https://yehsung.github.io/check/terms", MeText.termsOfServiceURL)
    }
}
