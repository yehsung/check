// 원본: Sources/check/CheckApp.swift:222-241 @ a63fea2 (매 실행 되살림 · 사용자가 끈 것 존중 · 실패는 다음에 다시) — 시험은 새 코드. 가짜 LoginItem.
package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class LoginItemBindingTest {
    /** Run 값 하나 + 작업 관리자 끔 표시 + 쓰기 실패 스위치. */
    private class FakeLoginItem : LoginItem {
        var runValue = false
        var systemDisabled = false
        var writable = true
        val calls = mutableListOf<Boolean>()
        override fun isEnabled() = runValue && !systemDisabled
        override fun setEnabled(enabled: Boolean): Boolean {
            calls += enabled
            if (!writable || (enabled && systemDisabled) || runValue == enabled) return false
            runValue = enabled
            return true
        }
    }

    @Test
    fun `첫 값부터 적용(앱 시작마다 되살림) · 끄면 지움 · 같은 값은 다시 쓰지 않음`() = runTest {
        val item = FakeLoginItem()
        val want = MutableStateFlow(true)
        val b = LoginItemBinding(item, want, StandardTestDispatcher(testScheduler), disabledBySystem = { item.systemDisabled })
        b.start(backgroundScope)
        runCurrent()
        assertEquals(LoginItemStatus.ON, b.status.value)
        assertEquals(true, item.runValue)
        want.value = true
        runCurrent()
        assertEquals(listOf(true), item.calls)
        want.value = false
        runCurrent()
        assertEquals(LoginItemStatus.OFF, b.status.value)
        assertEquals(false, item.runValue)
    }

    @Test
    fun `작업 관리자에서 끈 것은 되살리지 않고 BLOCKED_BY_SYSTEM · 쓰기 실패는 FAILED 뒤 reapply 로 회복`() = runTest {
        val item = FakeLoginItem().apply { systemDisabled = true }
        val b = LoginItemBinding(item, MutableStateFlow(true), StandardTestDispatcher(testScheduler), disabledBySystem = { item.systemDisabled })
        b.start(backgroundScope)
        runCurrent()
        assertEquals(LoginItemStatus.BLOCKED_BY_SYSTEM, b.status.value)
        assertEquals(false, item.runValue)

        val broken = FakeLoginItem().apply { writable = false }
        val c = LoginItemBinding(broken, MutableStateFlow(true), StandardTestDispatcher(testScheduler), disabledBySystem = { false })
        c.start(backgroundScope)
        runCurrent()
        assertEquals(LoginItemStatus.FAILED, c.status.value)
        broken.writable = true
        c.reapply()
        runCurrent()
        assertEquals(LoginItemStatus.ON, c.status.value)
    }

    @Test
    fun `MSIX(loginItem 없음)는 UNMANAGED — 아무것도 부르지 않는다`() = runTest {
        val b = LoginItemBinding(null, MutableStateFlow(true), StandardTestDispatcher(testScheduler))
        b.start(backgroundScope)
        runCurrent()
        assertEquals(LoginItemStatus.UNMANAGED, b.status.value)
    }
}
