// 원본: Sources/check/WorkShortcut.swift:36-46 @ a63fea2 (조합 규칙) — 시험은 새 코드: 설계 D§6(겹치면 1409) · D§2-2(창 스레드에서만)
//       · W0-e 실측 · G §2-3 W1-f ①(러너 2종)
package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.WindowsHotkeyService
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * G §2-3 W1-f ① 단축키 등록과 겹침 실패 코드(러너 2종). 맥 Carbon 과 달리 Windows 는 겹침을 1409 로 알려 준다(D§6, W0-e 실측).
 * 성공은 '등록됨' 상태만이 아니라 실제 키 입력이 콜백까지 오는지로도 잰다(CI·시험 VM 에서만 — 입력 주입).
 */
@EnabledOnOs(OS.WINDOWS)
class HotkeyWindowsTest {
    @Test
    fun secondRegistrationOfTheSameChordIsAConflictWith1409() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Hk")).use { thread ->
            WindowsHotkeyService(thread).use { svc ->
                val first = svc.register(HotkeyPolicy.DEFAULT) {}
                assertIs<HotkeyRegistrationResult.Registered>(first, "기본 조합 등록 실패: $first")
                assertEquals(HotkeyRegistrationResult.Conflict(Win32.ERROR_HOTKEY_ALREADY_REGISTERED), svc.register(HotkeyPolicy.DEFAULT) {})
                first.registration.close()
                val again = svc.register(HotkeyPolicy.DEFAULT) {}
                assertIs<HotkeyRegistrationResult.Registered>(again, "해제 뒤 다시 등록이 안 된다")
                again.registration.close()
            }
        }
    }

    @Test
    fun anotherWindowHoldingTheChordIsAConflict() {
        // '다른 앱이 쓰는 조합' 꼴: 다른 스레드·다른 창이 먼저 쥐고 있다.
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.HkA")).use { a ->
            Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.HkB")).use { b ->
                WindowsHotkeyService(a).use { svcA ->
                    WindowsHotkeyService(b).use { svcB ->
                        val held = svcA.register(HotkeyPolicy.DEFAULT) {}
                        assertIs<HotkeyRegistrationResult.Registered>(held)
                        assertEquals(HotkeyRegistrationResult.Conflict(Win32.ERROR_HOTKEY_ALREADY_REGISTERED), svcB.register(HotkeyPolicy.DEFAULT) {})
                        held.registration.close()
                        assertIs<HotkeyRegistrationResult.Registered>(svcB.register(HotkeyPolicy.DEFAULT) {})
                    }
                }
            }
        }
    }

    @Test
    fun injectedChordReachesTheCallback() {
        assumeTrue(RunnerSupport.inputInjectionAllowed(), "입력 주입은 CI·시험 VM 에서만")
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.HkIn")).use { thread ->
            WindowsHotkeyService(thread).use { svc ->
                val fired = CountDownLatch(1)
                val r = svc.register(HotkeyPolicy.DEFAULT) { fired.countDown() }
                assertIs<HotkeyRegistrationResult.Registered>(r)
                val sent = listOf(
                    Inject.key(Inject.VK_CONTROL, up = false), Inject.key(Inject.VK_MENU, up = false), Inject.key(Inject.VK_SHIFT, up = false),
                    Inject.key(Inject.VK_SPACE, up = false), Inject.key(Inject.VK_SPACE, up = true),
                    Inject.key(Inject.VK_SHIFT, up = true), Inject.key(Inject.VK_MENU, up = true), Inject.key(Inject.VK_CONTROL, up = true),
                ).sum()
                assertEquals(8, sent, "SendInput 이 막혔다(대화형 세션이 아니거나 UIPI)")
                assertTrue(fired.await(5, TimeUnit.SECONDS), "WM_HOTKEY 가 콜백까지 오지 않았다")
                r.registration.close()
            }
        }
    }
}
