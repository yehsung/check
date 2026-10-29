// 원본: 없음(맥 상태 아이템엔 오른쪽 메뉴가 없다) — 설계 D-windows-platform §3-3("오른쪽 클릭 메뉴: 근무 시작/종료, 열기, 설정, 종료.
//       맥 팝오버 레일의 바로가기를 일부 넣는다") · ★4 프로그램으로 여는 문은 하나(FlyoutNavigator.open).
// 그리는 일(TrackPopupMenuEx)은 shell/flyout/native/NativeTrayMenu — 여기는 항목·동작만(순수).
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute

enum class TrayMenuItemId { TOGGLE_WORK, OPEN, MESSAGES, SETTINGS, QUIT }

/** [id] 가 null 이면 구분선. */
data class TrayMenuItem(val id: TrayMenuItemId?, val label: String, val enabled: Boolean = true) {
    companion object {
        val SEPARATOR = TrayMenuItem(null, "")
    }
}

object TrayMenuModel {
    const val START_WORK = "근무 시작"
    const val END_WORK = "근무 종료"
    const val OPEN = "아잉체크 열기"
    const val MESSAGES = "메시지"
    const val SETTINGS = "설정"
    const val QUIT = "종료"

    /** 근무 글은 상태만 본다(대기여도 근무 중이면 '근무 종료' — 큐가 나중에 올린다). 로그인 전이면 근무 칸을 끈다. */
    fun items(work: WorkStatusSnapshot, signedIn: Boolean): List<TrayMenuItem> = listOf(
        TrayMenuItem(TrayMenuItemId.TOGGLE_WORK, if (work.isWorking) END_WORK else START_WORK, enabled = signedIn),
        TrayMenuItem.SEPARATOR,
        TrayMenuItem(TrayMenuItemId.OPEN, OPEN),
        TrayMenuItem(TrayMenuItemId.MESSAGES, MESSAGES, enabled = signedIn),
        TrayMenuItem(TrayMenuItemId.SETTINGS, SETTINGS),
        TrayMenuItem.SEPARATOR,
        TrayMenuItem(TrayMenuItemId.QUIT, QUIT),
    )
}

/** 메뉴를 띄우고 고른 항목을 돌려준다(없으면 null). Windows 구현 = NativeTrayMenu. */
fun interface TrayMenuPresenter {
    fun show(items: List<TrayMenuItem>, screenX: Int, screenY: Int): TrayMenuItemId?
}

/** 고른 항목 → 동작. 여는 길은 전부 [FlyoutNavigator.open] 하나(★4). */
class TrayMenuActions(
    private val toggleWork: () -> Unit,
    private val nav: FlyoutNavigator,
    private val quit: () -> Unit,
) {
    fun perform(id: TrayMenuItemId) {
        when (id) {
            TrayMenuItemId.TOGGLE_WORK -> toggleWork()
            TrayMenuItemId.OPEN -> nav.open()
            TrayMenuItemId.MESSAGES -> nav.open(FlyoutRoute.Messages)
            TrayMenuItemId.SETTINGS -> nav.open(FlyoutRoute.Settings)
            TrayMenuItemId.QUIT -> quit()
        }
    }

    /** 오른쪽 클릭 한 번: 띄우고, 고르면 한다. 껐던 칸은 골라도 하지 않는다. */
    fun onSecondaryClick(presenter: TrayMenuPresenter, items: List<TrayMenuItem>, screenX: Int, screenY: Int) {
        val picked = presenter.show(items, screenX, screenY) ?: return
        if (items.any { it.id == picked && it.enabled }) perform(picked)
    }
}
