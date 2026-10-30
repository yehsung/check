// W-13 #5 동의 끝까지 — AI 리밋 쪽. 맥 aiToolDataAllowed(WorkTimerStoreAILimits.swift:40-48 리더 문 · :116 값 행 문) ·
// setAIToolDataConsent(WorkTimerStoreMacEdition.swift:75-87 철회 = 마스터 끄기 + 표식, 동의 = 우리가 끈 마스터만 되살림).
// 실제 러너(AILimitWindowsRunner.live)에 세는 파일 읽기기만 끼우고, 제공자 HTTP·Supabase 둘 다 MockEngine 녹음. 실제 홈·계정·네트워크 0.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.nio.file.Path
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private const val T0 = 1_793_390_000.0

class AILimitConsentTest {
    private val homes = ArrayList<Path>()

    @AfterTest
    fun cleanUp() = homes.forEach(LimitsFixtures::delete)

    private inner class Rig {
        var consent = false
        val home: Path = LimitsFixtures.home("valid").also { homes.add(it) }
        val opened = mutableListOf<String>()
        /** 제공자 API(api.anthropic.com · chatgpt) — 자격 파일을 읽어야만 나간다. */
        val providerHttp = RecordingHttp(RecordingHttp.usage)
        /** Supabase(ai_limits upsert). */
        val supabase = RecordingHttp { respond("", HttpStatusCode.Created) }
        val kv = InMemoryDesktopKeyValueStore()
        val runner = AILimitWindowsRunner.live(DesktopAiHomes.synthetic(home), providerHttp.fetcher, "1") { p ->
            opened += p.fileName.toString()
            AILimitCredentialFiles.read(p)
        }
        val store = AILimitStore(kv, { SwiftDate(T0) }, { "SYNTH-PC" }, runner)
        val sync = DesktopAILimitSync(store, fakeService(supabase), { AILimitSession("tok", "user-1") }, { "win:5f1c0de0" }) { consent }

        fun rows(i: Int) = Json.parseToJsonElement(supabase.requests[i].bodyBytes().decodeToString()).jsonArray.map { it.jsonObject }
    }

    @Test
    fun beforeConsentZeroFileOpensZeroProviderCallsZeroUploadsThenGrantRunsThenRevokeStopsAgain() = runTest {
        val r = Rig()
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0), force = true)
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0 + 700), force = true)
        assertEquals(emptyList(), r.opened, "동의 전: 자격 파일 열기 0")
        assertEquals(0, r.providerHttp.requests.size, "동의 전: 제공자 API 0")
        assertEquals(0, r.supabase.requests.size, "동의 전: ai_limits 요청 0")
        assertEquals(null, r.kv.getString(AILimitStore.lastAttemptKey), "동의 전: 주기도 쓰지 않는다(동의 즉시 다음 틱이 돈다)")

        r.consent = true
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0 + 1400), force = true)
        assertEquals(setOf(".credentials.json", "auth.json"), r.opened.toSet(), "동의 뒤: 두 자격 파일을 읽는다")
        assertEquals(2, r.providerHttp.requests.size)
        assertEquals(1, r.supabase.requests.size, "동의 뒤: 값 행 업로드 1")
        assertTrue(r.rows(0).all { it["five_hour_percent"].toString() != "null" }, "값 행: ${r.rows(0)}")

        // 철회(설정 스위치가 키를 먼저 내리고 → 배선이 applyAIToolDataConsent(false)).
        r.consent = false
        r.sync.applyAIToolDataConsent(false)
        assertFalse(r.store.visibility.masterEnabled, "철회 → 마스터 끔(맥 setAILimitsVisible 같은 문)")
        assertTrue(r.store.pausedByConsent)
        assertEquals(2, r.supabase.requests.size, "철회 순간 비우는 행 한 번(폰·위젯에서 사라지게)")
        assertTrue(r.rows(1).all { it["five_hour_percent"].toString() == "null" }, "비우기만 — 값 0: ${r.rows(1)}")
        val openedBefore = r.opened.size
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0 + 2800), force = true)
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0 + 4200), force = true)
        assertEquals(openedBefore, r.opened.size, "철회 뒤: 자격 파일 열기 0")
        assertEquals(2, r.providerHttp.requests.size, "철회 뒤: 제공자 API 0")
        assertEquals(2, r.supabase.requests.size, "철회 뒤: ai_limits 요청 0")

        // 동의 없이 사용자가 마스터를 다시 켜도 옛 값 행은 싣지 않는다(맥 :116 — 묶음이 비어 요청 0).
        r.sync.setAILimitsVisible(true)
        assertFalse(r.store.pausedByConsent, "사용자가 직접 만지면 표식은 지운다")
        assertEquals(2, r.supabase.requests.size, "동의 없이 마스터를 켜도 값 행 0")

        // 다시 동의 → 값이 다시 나간다(양성 짝).
        r.consent = true
        r.sync.applyAIToolDataConsent(true)
        assertTrue(r.store.visibility.masterEnabled)
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0 + 5600), force = true)
        assertEquals(3, r.supabase.requests.size)
        assertTrue(r.rows(2).all { it["five_hour_percent"].toString() != "null" }, "다시 동의 → 값 행")
    }

    @Test
    fun grantRevivesOnlyTheMasterWeTurnedOff() = runTest {
        val r = Rig()
        r.consent = true
        r.sync.refreshAILimitsIfNeeded(SwiftDate(T0), force = true)
        r.consent = false
        r.sync.applyAIToolDataConsent(false)
        assertTrue(r.store.pausedByConsent)
        r.consent = true
        r.sync.applyAIToolDataConsent(true)
        assertTrue(r.store.visibility.masterEnabled, "우리가 끈 마스터는 되살린다")
        assertFalse(r.store.pausedByConsent)
    }

    @Test
    fun userTurnedOffMasterIsNotRevivedByConsentAndRevokeWithoutValuesSendsNothing() = runTest {
        val r = Rig()
        r.consent = true
        r.sync.setAILimitsVisible(false)            // 사용자가 직접 끔(읽은 값이 없으니 비우기도 없다)
        assertEquals(0, r.supabase.requests.size)
        r.consent = false
        r.sync.applyAIToolDataConsent(false)
        assertFalse(r.store.pausedByConsent, "이미 꺼진 마스터는 우리가 끈 게 아니다")
        r.consent = true
        r.sync.applyAIToolDataConsent(true)
        assertFalse(r.store.visibility.masterEnabled, "사용자가 꺼 둔 마스터는 동의가 되살리지 않는다")
        assertEquals(0, r.supabase.requests.size, "읽은 값이 없으면 철회·동의 어느 쪽도 요청 0")
    }
}
