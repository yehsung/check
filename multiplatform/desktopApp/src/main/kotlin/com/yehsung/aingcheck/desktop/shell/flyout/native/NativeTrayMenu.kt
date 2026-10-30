// 원본: 없음(새 코드) — 설계 D-windows-platform §3-3 오른쪽 클릭 메뉴 · learn.microsoft.com TrackPopupMenuEx Remarks:
//       "메뉴 전에 SetForegroundWindow, 뒤에 WM_NULL 을 보내야" 바깥 클릭으로 메뉴가 닫힌다(알림 영역 메뉴의 알려진 규칙).
// 메뉴는 메시지 창 스레드에서 돈다(TrackPopupMenuEx 는 그 창 스레드의 모달 루프). 트레이 클릭 듣기가 그 스레드라 call 이 바로 돈다.
package com.yehsung.aingcheck.desktop.shell.flyout.native

import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.WString
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.win32.StdCallLibrary
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuItem
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuItemId
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuPresenter

internal interface MenuApi : StdCallLibrary {
    fun CreatePopupMenu(): Pointer?
    fun AppendMenuW(menu: Pointer, flags: Int, id: Long, text: WString?): Boolean
    fun TrackPopupMenuEx(menu: Pointer, flags: Int, x: Int, y: Int, hwnd: WinDef.HWND, params: Pointer?): Int
    fun DestroyMenu(menu: Pointer): Boolean

    companion object {
        val INSTANCE: MenuApi by lazy { Native.load("user32", MenuApi::class.java) }
    }
}

class NativeTrayMenu(private val thread: Win32MessageThread) : TrayMenuPresenter {
    override fun show(items: List<TrayMenuItem>, screenX: Int, screenY: Int): TrayMenuItemId? =
        thread.call(timeoutMillis = 10 * 60_000L) { hwnd ->
            val api = MenuApi.INSTANCE
            val menu = api.CreatePopupMenu() ?: return@call null
            try {
                items.forEachIndexed { i, item ->
                    if (item.id == null) {
                        api.AppendMenuW(menu, MF_SEPARATOR, 0, null)
                    } else {
                        api.AppendMenuW(menu, MF_STRING or (if (item.enabled) 0 else MF_GRAYED), (i + 1).toLong(), WString(item.label))
                    }
                }
                User32.INSTANCE.SetForegroundWindow(hwnd)
                val cmd = api.TrackPopupMenuEx(menu, TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_NONOTIFY, screenX, screenY, hwnd, null)
                User32.INSTANCE.PostMessage(hwnd, WM_NULL, WinDef.WPARAM(0), WinDef.LPARAM(0))
                items.getOrNull(cmd - 1)?.id
            } finally {
                api.DestroyMenu(menu)
            }
        }

    private companion object {
        const val MF_STRING = 0x0000
        const val MF_GRAYED = 0x0001
        const val MF_SEPARATOR = 0x0800
        const val TPM_RIGHTBUTTON = 0x0002
        const val TPM_NONOTIFY = 0x0080
        const val TPM_RETURNCMD = 0x0100
        const val WM_NULL = 0x0000
    }
}
