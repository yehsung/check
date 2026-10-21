package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.sun.jna.Native
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.desktop.platform.windows.jna.NOTIFYICONDATAW
import com.yehsung.aingcheck.desktop.platform.windows.jna.NOTIFYICONIDENTIFIER
import com.yehsung.aingcheck.desktop.platform.windows.jna.Shell32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayCallbackDecoder
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconRenderer
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconSpec
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconStatus
import com.yehsung.aingcheck.desktop.platform.windows.tray.WindowsTrayHost
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * G §2-3 W1-f ① 트레이 추가·삭제(러너 2종). 성공은 우리 상태값이 아니라 **OS 에 다시 물어서** 잰다:
 * Shell_NotifyIconGetRect 는 아이콘이 있을 때만 S_OK — 추가 뒤 S_OK, 삭제 뒤 실패(짝).
 * windows-11-arm 러너는 OOBE 개인정보 화면을 걷어야 NIM_ADD 가 된다(W0-e 실측 — CI 준비 단계, 조정자 패치).
 */
@EnabledOnOs(OS.WINDOWS)
class TrayWindowsTest {
    private val iconId = 7

    private fun icon(status: TrayIconStatus = TrayIconStatus.Off) =
        TrayIconRenderer.render(TrayIconSpec(status, redDot = false, theme = TaskbarTheme.DARK, sizePx = 24))

    /** 우리 코드와 따로, 이 창·id 의 아이콘이 셸에 있는지 OS 에 묻는다. */
    private fun shellHasIcon(thread: Win32MessageThread): Boolean = thread.call { hwnd ->
        val id = NOTIFYICONIDENTIFIER()
        id.cbSize = id.size()
        id.hWnd = hwnd
        id.uID = iconId
        Shell32X.INSTANCE.Shell_NotifyIconGetRect(id, WinDef.RECT()) == 0
    }

    @Test
    fun notifyIconDataIs976BytesOn64Bit() {
        assertEquals(8, Native.POINTER_SIZE)
        assertEquals(NOTIFYICONDATAW.EXPECTED_SIZE_64, NOTIFYICONDATAW().size())
    }

    @Test
    fun addVersionUpdateRemoveIsSeenByTheShell() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Tray")).use { thread ->
            assertFalse(shellHasIcon(thread), "시작 전에 아이콘이 있다")
            WindowsTrayHost(thread, iconId = iconId, retryWindowMillis = 20_000).use { tray ->
                tray.show(icon(), "aing-check 시험 아이콘")
                RunnerSupport.waitUntil(20_000, "NIM_ADD 성공(${tray.status()})") { tray.status().added }
                val st = tray.status()
                assertTrue(st.versionSet, "NOTIFYICON_VERSION_4 설정 실패: $st")
                assertTrue(shellHasIcon(thread), "셸이 아이콘을 모른다")
                val rect = tray.iconRect()
                assertNotNull(rect, "Shell_NotifyIconGetRect")
                assertTrue(rect.right > rect.left && rect.bottom > rect.top, "빈 사각형 $rect")
                println("AINGCHECK-TRAY addAttempts=${st.addAttempts} rect=$rect")

                tray.update(icon(TrayIconStatus.Working(3600)), "aing-check 근무 중 01:00")
                assertEquals(0, tray.status().lastError, "NIM_MODIFY 실패")
                assertTrue(shellHasIcon(thread))

                tray.remove()
                assertFalse(tray.status().added)
                assertFalse(shellHasIcon(thread), "NIM_DELETE 뒤에도 셸에 남았다")
                assertNull(tray.iconRect())
            }
        }
    }

    @Test
    fun taskbarCreatedBroadcastReattachesTheIcon() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.TrayRe")).use { thread ->
            WindowsTrayHost(thread, iconId = iconId, retryWindowMillis = 20_000).use { tray ->
                tray.show(icon(), "aing-check 재부착 시험")
                RunnerSupport.waitUntil(20_000, "NIM_ADD") { tray.status().added }
                // Explorer 가 다시 뜰 때의 방송을 이 창에 흉내 낸다(실제 explorer 재시작은 VM D-E02 몫).
                // 셸에서 먼저 지워 '아이콘이 사라진 Explorer' 를 만든다.
                thread.call { hwnd ->
                    val d = NOTIFYICONDATAW()
                    d.cbSize = d.size()
                    d.hWnd = hwnd
                    d.uID = iconId
                    Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_DELETE, d)
                }
                assertFalse(shellHasIcon(thread))
                User32X.INSTANCE.PostMessageW(thread.hwnd, thread.taskbarCreatedMessage, WinDef.WPARAM(0), WinDef.LPARAM(0))
                RunnerSupport.waitUntil(10_000, "TaskbarCreated 뒤 다시 붙음") { tray.status().reattached == 1 }
                assertTrue(shellHasIcon(thread), "다시 붙였다는데 셸에 없다")
            }
        }
    }

    @Test
    fun callbackMessageReachesClickListenersWithSignedCoordinates() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.TrayCb")).use { thread ->
            WindowsTrayHost(thread, iconId = iconId).use { tray ->
                val got = ArrayBlockingQueue<Triple<TrayClick, Int, Int>>(4)
                tray.addClickListener { c, x, y -> got.add(Triple(c, x, y)) }
                val (w, l) = TrayCallbackDecoder.encode(Win32.NIN_SELECT, iconId, -1500, 1060)
                // 다른 아이콘 id 의 콜백은 무시해야 한다.
                val (w2, l2) = TrayCallbackDecoder.encode(Win32.NIN_SELECT, iconId + 1, 1, 1)
                User32X.INSTANCE.PostMessageW(thread.hwnd, Win32.WM_APP_TRAY, WinDef.WPARAM(w2), WinDef.LPARAM(l2))
                User32X.INSTANCE.PostMessageW(thread.hwnd, Win32.WM_APP_TRAY, WinDef.WPARAM(w), WinDef.LPARAM(l))
                val first = got.poll(5, TimeUnit.SECONDS)
                assertEquals(Triple(TrayClick.PRIMARY, -1500, 1060), first)
                assertNull(got.poll(300, TimeUnit.MILLISECONDS), "다른 아이콘의 콜백이 새었다")
            }
        }
    }

    @Test
    fun messageThreadRunsCallsOnItsOwnThreadAndStops() {
        val thread = Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Msg"))
        val me = Thread.currentThread()
        val ran = thread.call { Thread.currentThread() }
        assertNotEquals(me, ran)
        assertEquals(ran, thread.call { Thread.currentThread() }, "호출마다 다른 스레드")
        thread.close()
        assertFalse(thread.isAlive)
    }
}
