package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.desktop.platform.windows.input.WindowsIdleSource
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.util.concurrent.atomic.AtomicLong
import kotlin.time.Clock
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

/**
 * G §2-3 W1-f ① Raw Input 등록(러너 2종). 등록 성공은 **OS 에 다시 물어서**(GetRegisteredRawInputDevices) 잰다 — 등록 뒤 키보드·마우스
 * 두 줄(RIDEV_INPUTSINK), 해제 뒤 0줄(짝). CI·시험 VM 에서는 실제 입력을 주입해 맥 계약(이동만은 사용 중이 아니다)까지 잰다(D-E05 의 러너 몫).
 */
@EnabledOnOs(OS.WINDOWS)
class RawInputWindowsTest {
    /** 부를 때마다 1ms 가는 시험 시계(벽시계는 앱 조립 지점에서만 — 구조 시험 R2). */
    private class TickingClock : Clock {
        private val ms = AtomicLong(0)
        override fun now(): Instant = Instant.parse("2026-09-17T05:05:00Z") + ms.incrementAndGet().milliseconds
    }

    @Test
    fun registersKeyboardAndMouseSinkAndRemovesOnClose() {
        val clock = TickingClock()
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Raw")).use { thread ->
            val idle = WindowsIdleSource(thread, clock)
            assertEquals(emptyList(), idle.registeredDevices(), "시작 전에 이미 등록돼 있다")
            assertEquals(WindowsIdleSource.Mode.RAW_INPUT, idle.start(), "등록 실패 코드 ${idle.registrationError}")
            val regs = idle.registeredDevices().toSet()
            assertEquals(
                setOf(
                    Triple(Win32.HID_USAGE_PAGE_GENERIC, Win32.HID_USAGE_GENERIC_KEYBOARD, Win32.RIDEV_INPUTSINK),
                    Triple(Win32.HID_USAGE_PAGE_GENERIC, Win32.HID_USAGE_GENERIC_MOUSE, Win32.RIDEV_INPUTSINK),
                ),
                regs,
            )
            idle.close()
            assertEquals(emptyList(), idle.registeredDevices(), "해제 뒤에도 남았다")
        }
    }

    @Test
    fun injectedInputIsClassifiedAndMovementAloneDoesNotCount() {
        assumeTrue(RunnerSupport.inputInjectionAllowed(), "입력 주입은 CI·시험 VM 에서만")
        val clock = TickingClock()
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.RawIn")).use { thread ->
            val idle = WindowsIdleSource(thread, clock)
            val seen = LinkedBlockingQueue<InputKind>()
            idle.addListener { kind, _ -> seen.add(kind) }
            assertEquals(WindowsIdleSource.Mode.RAW_INPUT, idle.start())
            val meaningful = setOf(InputKind.KEY, InputKind.CLICK, InputKind.WHEEL)

            fun expect(kind: InputKind) {
                val deadline = System.nanoTime() + 5_000_000_000L
                while (System.nanoTime() < deadline) {
                    val k = seen.poll(100, TimeUnit.MILLISECONDS) ?: continue
                    if (k == kind) return
                }
                throw AssertionError("$kind 를 5초 안에 받지 못했다")
            }

            // ① 이동만 — 리스너는 MOVE 를 받지만 '의미 있는 입력' 시각은 생기지 않는다(맥 CheckWorkNudge 계약).
            assertEquals(1, Inject.mouseMove(1, 0))
            expect(InputKind.MOVE)
            assertEquals(1, Inject.mouseMove(-1, 0))
            Thread.sleep(200)
            assertNull(idle.lastInput(meaningful), "마우스 이동만으로 사용 중이 됐다")
            assertNotNull(idle.lastInput(setOf(InputKind.MOVE)))

            // ② 휠
            assertEquals(1, Inject.wheel(120))
            expect(InputKind.WHEEL)
            assertEquals(1, Inject.wheel(-120))
            assertNotNull(idle.lastInput(setOf(InputKind.WHEEL)))
            assertNull(idle.lastInput(setOf(InputKind.KEY, InputKind.CLICK)))

            // ③ 키: 누름만 센다(뗌은 KEY 를 만들지 않는다).
            seen.clear()
            assertEquals(1, Inject.key(Inject.VK_F24, up = false))
            assertEquals(1, Inject.key(Inject.VK_F24, up = true))
            expect(InputKind.KEY)
            Thread.sleep(300)
            assertEquals(0, seen.count { it == InputKind.KEY }, "키를 한 번 눌렀는데 KEY 가 두 번 왔다(뗌을 셌다)")

            // ④ 단추(X1): 누름 = CLICK, 뗌 = 없음.
            seen.clear()
            assertEquals(1, Inject.xButton(up = false))
            assertEquals(1, Inject.xButton(up = true))
            expect(InputKind.CLICK)
            Thread.sleep(300)
            assertEquals(0, seen.count { it == InputKind.CLICK }, "단추 뗌을 클릭으로 셌다")

            val last = idle.lastInput(meaningful)
            assertNotNull(last)
            assertTrue(last <= clock.now(), "미래 시각")
            idle.close()
        }
    }
}
