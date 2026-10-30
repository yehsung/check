// 원본: Sources/check/CheckMiniGameWindow.swift:150-243(지연 생성 · 멱등 열기 · 닫아도 파괴 안 함) ·
//       CheckGomokuWindow.swift:384-419(고착 감시자 0.5초 · 재생성 3회 상한) · CheckMiniGameWindow.swift ★342(재생성 때 자리 키 놓기)
//       (W4-d 창 공통 부품 — 창 하나의 수명 규약. 실제 창은 [GameWindowHandle] 뒤에 있어 시험은 창 0 으로 잰다)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect

/** 실제 창(ComposeWindow 등)을 감싸는 얇은 손잡이. W4-e·f 가 구현한다. */
interface GameWindowHandle {
    val isMinimized: Boolean
    /** 화면에 실제로 떠 있는가(최소화 아님 ∧ 보임). 고착 감시가 읽는다. */
    val isOnScreen: Boolean
    fun restoreFromMinimized()
    fun showAndFocus()
    /** 숨긴다 — 파괴하지 않는다(자리·상태 보존). */
    fun hide()
    fun boundsPx(): PxRect
    fun setBoundsPx(rect: PxRect)
    /** 고착 감시가 재생성할 때만 부른다. */
    fun dispose()
}

/**
 * 창 하나의 수명. ① 지연 생성 ② 멱등 열기(최소화면 되살림) ③ 닫아도 파괴 안 함 ④ 자리는 [GameWindowKind.boundsKey] 로 저장·복원
 * ⑤ 고착 감시 — 열렸다고 믿는데 화면에 없으면 다시 만든다([MAX_RECREATIONS] 상한). 사건은 전부 [GameWindowEvents] 표로 통지한다.
 */
class GameWindowSlot(
    val kind: GameWindowKind,
    private val create: () -> GameWindowHandle,
    private val bounds: WindowBoundsStore,
    private val workAreas: () -> List<PxRect>,
    private val scale: () -> Double,
    private val onNotices: (List<StoreNotice>) -> Unit,
) {
    private var handle: GameWindowHandle? = null

    var presence: WindowPresence = WindowPresence()
        private set
    var recreations: Int = 0
        private set
    val isCreated: Boolean get() = handle != null

    fun open() {
        val h = handle ?: create().also { created ->
            handle = created
            val size = WindowBoundsRule.sizePx(kind.defaultWidthDp, kind.defaultHeightDp, scale())
            created.setBoundsPx(WindowBoundsRule.restore(bounds.load(kind.boundsKey), workAreas(), size))
        }
        if (h.isMinimized) h.restoreFromMinimized()
        h.showAndFocus()
        dispatch(WindowEvent.Shown)
    }

    /** 프로그램 닫기(로그아웃·계정 전환·closeAll). 열려 있지 않으면 아무 일도 없다(멱등). */
    fun closeFromApp() {
        val h = handle ?: return
        if (!presence.open) return
        bounds.save(kind.boundsKey, h.boundsPx())
        h.hide()
        dispatch(WindowEvent.AppClosed)
    }

    /** 껍데기가 Win32/AWT 사건을 넘긴다. UserClosed 면 숨기기만 한다(파괴 안 함). */
    fun onEvent(event: WindowEvent) {
        val h = handle ?: return
        if (event == WindowEvent.UserClosed) {
            if (!presence.open) return
            bounds.save(kind.boundsKey, h.boundsPx())
            h.hide()
        }
        dispatch(event)
    }

    /** 창이 움직이거나 크기가 바뀌었을 때(껍데기가 디바운스해서 부른다). */
    fun rememberBounds() {
        handle?.let { bounds.save(kind.boundsKey, it.boundsPx()) }
    }

    /**
     * 고착 감시(맥은 열기 0.5초 뒤 — [STUCK_CHECK_DELAY_MS]). 열렸다고 믿는데 화면에 없으면 자리를 저장하고 버린 뒤 다시 연다.
     * 재생성은 [MAX_RECREATIONS] 번까지. 다시 만들었으면 true.
     */
    fun checkStuck(): Boolean {
        val h = handle ?: return false
        if (!presence.open || h.isMinimized || h.isOnScreen) return false
        if (recreations >= MAX_RECREATIONS) return false
        bounds.save(kind.boundsKey, h.boundsPx())
        h.dispose()
        handle = null
        recreations++
        open()
        return true
    }

    private fun dispatch(event: WindowEvent) {
        val notices = GameWindowEvents.notices(kind, event, presence)
        presence = presence.after(event)
        if (notices.isNotEmpty()) onNotices(notices)
    }

    companion object {
        const val STUCK_CHECK_DELAY_MS = 500L
        const val MAX_RECREATIONS = 3
    }
}
