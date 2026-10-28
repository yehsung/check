// 원본: Tests/CheckMobileKitTests/AvatarCharacterTests.swift(AppUserCharacterStore 몫 — 스로틀 · 내 칸 · 로그아웃 · 늦은 응답) @ 1b8260d
package com.yehsung.aingcheck.core.stores.characters

import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

@OptIn(ExperimentalCoroutinesApi::class)
class AppUserCharacterStoreTest {
    private val me = StoreHarness.ME
    private val known = listOf("aing", "fox", "robot")

    @Test
    fun refreshThrottlesMyEquipWinsOverLateRowsAndResetClears() = runTest {
        val gate = CompletableDeferred<Unit>()
        var calls = 0
        val h = StoreHarness(this) { r ->
            if (r.rpcName == "app_user_characters") {
                calls += 1
                val rows = """[{"user_id":"${me.uppercase()}","character":"fox"},{"user_id":"u-2","character":"robot"},{"user_id":"u-3","character":"unknown-x"}]"""
                if (calls == 2) Reply.Gate(gate, Reply.Json(rows)) else Reply.Json(rows)
            } else null
        }
        h.signIn()
        val store = AppUserCharacterStore(h.context, h.storeScope, known)
        var changes = 0
        store.onDirectoryChange = { changes += 1 }
        store.refresh()
        advanceUntilIdle()
        assertEquals("fox", store.directory.characterID(me), "user id 는 대소문자를 가리지 않는다")
        assertEquals("robot", store.directory.characterID("u-2"))
        assertNull(store.directory.characterID("u-3"), "모르는 캐릭터는 이니셜")
        assertEquals(1, changes)
        // 60초 안의 기존 갱신 시점은 묻지 않는다(실패도 시도로 센다).
        store.refreshIfStale()
        advanceUntilIdle()
        assertEquals(1, calls)
        advanceTimeBy(61_000)
        store.refreshIfStale()
        runCurrent()
        // 조회가 떠 있는 동안 내가 로봇으로 갈아입었다 — 늦게 온 옛 표(fox)가 되돌리지 않는다.
        store.noteMyEquipped("robot")
        assertEquals("robot", store.directory.characterID(me))
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals("robot", store.directory.characterID(me), "늦은 조회가 방금 입은 캐릭터를 되돌렸다")
        store.reset()
        assertNull(store.directory.characterID("u-2"), "로그아웃 뒤 앞 계정의 표가 남았다")
        assertNull(store.lastAttemptAt)
        h.assertClean()
    }

    @Test
    fun finishWithStaleSerialIsIgnored() = runTest {
        val h = StoreHarness(this) { r -> if (r.rpcName == "app_user_characters") Reply.Json("[]") else null }
        h.signIn()
        val store = AppUserCharacterStore(h.context, h.storeScope, known)
        store.finish(listOf(AppUserCharacterRow("u-9", "fox")), serial = store.requestSerial + 5, generation = h.context.generation)
        assertNull(store.directory.characterID("u-9"), "떠날 때의 순번이 아닌 응답을 반영했다")
        store.finish(listOf(AppUserCharacterRow("u-9", "fox")), serial = store.requestSerial, generation = h.context.generation + 1)
        assertNull(store.directory.characterID("u-9"), "다른 세대의 응답을 반영했다")
        store.finish(listOf(AppUserCharacterRow("u-9", "fox")), serial = store.requestSerial, generation = h.context.generation)
        assertEquals("fox", store.directory.characterID("u-9"))
        h.assertClean()
    }
}
