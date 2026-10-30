// 원본: 없음(새 코드) — W-14 #4(WM_DISPLAYCHANGE → overlay.onDisplayChanged) · W5-b4 notes("WindowsPlatform 에 디스플레이 변경 통지 자리가 없어
// 오버레이 자리 재배치는 다음 시작 때만"). 맥은 NSApplication.didChangeScreenParametersNotification 이 같은 몫이다(화면 연결·해제·배율·Dock 이동).
//
// 출처 고르기: **숨은 최상위 창의 방송 메시지**(Win32MessageThread — WS_POPUP 숨은 창, HWND_MESSAGE 아님)를 쓴다.
//  - WM_DISPLAYCHANGE(0x007E): 모니터 연결·해제·해상도 — 모든 최상위 창에 방송된다(message-only 창은 못 받는다 — 그래서 그 창이 최상위다).
//  - WM_DPICHANGED(0x02E0): 그 창이 있는 모니터의 배율이 바뀌었다(Per-Monitor 인식 프로세스).
//  - WM_SETTINGCHANGE(0x001A) + SPI_SETWORKAREA(0x002F): 작업 표시줄 이동·자동 숨김 — 작업 영역이 바뀌어 캐릭터를 다시 조여야 한다.
//  AWT GraphicsEnvironment 화면 목록을 주기 비교하는 길은 버렸다: ① 한가할 때도 깨어나 비교한다(배터리) ② 주기만큼 늦다
//  ③ AWT 장치 목록은 AWT 자체 창 프로시저가 갱신해야 바뀌어 같은 사건을 한 번 더 건너 받는다 ④ 작업 영역(작업 표시줄)은 목록에 없다.
//  메시지 길은 사건이 날 때만 돌고, 같은 숨은 창이 이미 TaskbarCreated 방송을 받는 검증된 자리다.
//
// 처리기는 null 을 돌려준다(다음 처리기 · DefWindowProc 그대로 — 다른 서비스가 같은 메시지를 볼 수 있다). 처리기는 메시지 스레드에서 돈다 —
// 받는 쪽(OverlayWiring.onDisplayChanged)은 명령 채널에 넣기만 하고 바로 돌아온다.
package com.yehsung.aingcheck.desktop.platform.windows.display

import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.msg.MessageHandler
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread

/** 화면 구성이 바뀐 까닭(진단 · 시험). 받는 쪽은 종류와 무관하게 모니터를 다시 읽는다. */
enum class DisplayChange {
    /** WM_DISPLAYCHANGE — 연결·해제·해상도. */
    DISPLAY_MODE,
    /** WM_DPICHANGED — 배율. */
    DPI,
    /** WM_SETTINGCHANGE(SPI_SETWORKAREA) — 작업 영역(작업 표시줄). */
    WORK_AREA,
}

/** 화면 구성 바뀜 출처. [addListener] 의 Registration 을 닫으면 그 뒤 통지 0. */
fun interface DisplayChangeSource {
    fun addListener(listener: (DisplayChange) -> Unit): Registration

    companion object {
        /** 출처 없음(맥 개발 실행 · 시험 기본). */
        val None: DisplayChangeSource = DisplayChangeSource { Registration { } }
    }
}

/** Win32 메시지 번호(winuser.h). */
object DisplayMessages {
    const val WM_DISPLAYCHANGE: Int = 0x007E
    const val WM_DPICHANGED: Int = 0x02E0
    const val WM_SETTINGCHANGE: Int = 0x001A
    const val SPI_SETWORKAREA: Long = 0x002F

    /** 이 메시지가 화면 구성 바뀜인가. WM_SETTINGCHANGE 는 wParam 이 SPI_SETWORKAREA 일 때만(글꼴·테마 같은 다른 설정은 아니다). */
    fun classify(message: Int, wParam: Long): DisplayChange? = when (message) {
        WM_DISPLAYCHANGE -> DisplayChange.DISPLAY_MODE
        WM_DPICHANGED -> DisplayChange.DPI
        WM_SETTINGCHANGE -> if (wParam == SPI_SETWORKAREA) DisplayChange.WORK_AREA else null
        else -> null
    }

    val all: List<Int> = listOf(WM_DISPLAYCHANGE, WM_DPICHANGED, WM_SETTINGCHANGE)
}

/**
 * 숨은 창 메시지 → [DisplayChange]. [register] 는 `Win32MessageThread::addHandler`(시험은 가짜). 듣는 이가 처음 붙을 때 메시지 셋에
 * 처리기를 걸고, 모두 떨어지면 푼다.
 */
class Win32DisplayChangeSource(
    private val register: (message: Int, handler: MessageHandler) -> Registration,
) : DisplayChangeSource {
    private val lock = Any()
    private val listeners = ArrayList<(DisplayChange) -> Unit>()
    private var hooks: List<Registration> = emptyList()

    private val handler = MessageHandler { _, message, wParam, _ ->
        DisplayMessages.classify(message, wParam.toLong())?.let(::fire)
        null
    }

    override fun addListener(listener: (DisplayChange) -> Unit): Registration {
        synchronized(lock) {
            if (listeners.isEmpty()) hooks = DisplayMessages.all.map { register(it, handler) }
            listeners += listener
        }
        return Registration {
            synchronized(lock) {
                if (!listeners.remove(listener)) return@Registration
                if (listeners.isEmpty()) {
                    hooks.forEach { runCatching { it.close() } }
                    hooks = emptyList()
                }
            }
        }
    }

    /** 걸린 메시지 처리기 수(시험 · 진단). */
    val hookCount: Int get() = synchronized(lock) { hooks.size }

    private fun fire(change: DisplayChange) {
        val snapshot = synchronized(lock) { listeners.toList() }
        snapshot.forEach { runCatching { it(change) } }
    }

    companion object {
        /** 앱 메시지 스레드(WindowsPlatform.messageThread)의 숨은 창으로 듣는다. */
        fun on(thread: Win32MessageThread): Win32DisplayChangeSource = Win32DisplayChangeSource(thread::addHandler)
    }
}
