// 원본: 없음(새 코드) — 핀 shellapi 조정 ⑨(BalloonNotifier: 구현 W1-f2, 사용 W3-c1) · shell.md §6 조정자 패치 3
//       (풍선 NIF_INFO·NIIF_RESPECT_QUIET_TIME·NIF_REALTIME, NIN_BALLOONUSERCLICK 0x405 듣기, WM_SETTINGCHANGE("ImmersiveColorSet"))
//       · W-3 #6(같은 사건은 한 표면만: 말풍선 > 토스트(=이 풍선) > 빨간 점 — 고르기는 W3-c1 의 NotifyArbiter, 여기는 띄우기만)
//       · learn.microsoft.com NOTIFYICONDATAW(uFlags·dwInfoFlags·szInfoTitle 64·szInfo 256) · Shell_NotifyIcon 알림(NIN_BALLOON*)
//
// 이 파일은 **순수 함수**만 둔다(맥 JVM 시험이 JNA 없이 잰다). Shell_NotifyIcon 호출은 WindowsTrayHost.
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.desktop.shellapi.NotifyKind

/**
 * 풍선·테마에 쓰는 Win32 상수(shellapi.h·winuser.h 값 그대로). 공용 표 `jna/Win32` 는 이 갈래 소유 밖이라 여기 둔다 —
 * 통합 때 Win32 로 옮길 후보(coordinator_patches).
 */
object TrayBalloonWin32 {
    const val NIF_INFO = 0x10
    const val NIF_REALTIME = 0x40

    const val NIIF_NONE = 0x00
    const val NIIF_USER = 0x04
    const val NIIF_RESPECT_QUIET_TIME = 0x80

    const val NIN_BALLOONSHOW = 0x0400 + 2
    const val NIN_BALLOONHIDE = 0x0400 + 3
    const val NIN_BALLOONTIMEOUT = 0x0400 + 4
    const val NIN_BALLOONUSERCLICK = 0x0400 + 5

    const val WM_SETTINGCHANGE = 0x001A

    /** szInfoTitle[64]·szInfo[256] 의 글자 수 상한(끝 NUL 자리 뺌). */
    const val MAX_TITLE_CHARS = 63
    const val MAX_BODY_CHARS = 255
}

/** 풍선 한 번에 쓸 값. 글자는 아직 자르지 않았다 — 구조체에 넣을 때 NOTIFYICONDATAW.clipUtf16 으로 자른다(자르기 규칙은 한 곳). */
data class BalloonPlan(val uFlags: Int, val dwInfoFlags: Int, val title: String, val body: String)

object BalloonPlanner {
    /**
     * 실시간 풍선(NIF_REALTIME: 지금 못 띄우면 버린다)인가. 메시지·콕·대결 신청은 지금의 사건이라 늦게 뜨면 거짓말이 된다
     * (늦은 사건은 빨간 점이 이미 말한다 — W-3 #6 점은 늘). 새 버전 안내는 늦게 떠도 참이라 대기열에 남긴다.
     */
    fun isRealtime(kind: NotifyKind): Boolean = when (kind) {
        NotifyKind.MESSAGE, NotifyKind.POKE, NotifyKind.DUEL_INVITE -> true
        NotifyKind.UPDATE -> false
    }

    /**
     * 본문이 비면 null(띄우지 않음): NIM_MODIFY 에 NIF_INFO + 빈 szInfo 는 **떠 있는 풍선을 지우라**는 뜻이다(문서) —
     * 빈 알림을 보내면 사용자에게는 아무 일도 없고 앞 풍선만 사라진다.
     * 아이콘은 NIIF_NONE(hBalloonIcon 없음) — Windows 10/11 은 풍선을 토스트로 바꿔 그리며 트레이 아이콘을 쓴다.
     * NIIF_USER 는 쓰지 않는다: hBalloonIcon 이 SM_CXSMICON 과 다른 크기면 셸이 NIM_MODIFY 를 FALSE·1462(ERROR_INCORRECT_SIZE)로
     * 거절한다(러너 2종 실측, mp-ci run 40960010244 — 24px 아이콘 · 100% 배율 16px). 배율이 바뀐 직후 트레이 아이콘이 그 상태다.
     */
    fun plan(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): BalloonPlan? {
        if (body.isBlank()) return null
        var flags = TrayBalloonWin32.NIF_INFO
        if (isRealtime(kind)) flags = flags or TrayBalloonWin32.NIF_REALTIME
        var info = TrayBalloonWin32.NIIF_NONE
        if (respectQuietTime) info = info or TrayBalloonWin32.NIIF_RESPECT_QUIET_TIME
        return BalloonPlan(flags, info, title, body)
    }
}

/** 풍선 콜백(NOTIFYICON_VERSION_4: LOWORD(lParam) = 사건, HIWORD(lParam) = 아이콘 id). */
enum class BalloonEventKind { SHOWN, HIDDEN, TIMED_OUT, USER_CLICKED }

data class BalloonEvent(val kind: BalloonEventKind, val iconId: Int)

/**
 * 작업 표시줄 밝음·어두움 변화 거르기. WM_SETTINGCHANGE 는 설정 아무거나 바뀌어도 온다(환경 변수·정책·글꼴…) —
 * lParam 글자가 "ImmersiveColorSet" 일 때만 레지스트리를 다시 읽고, 값이 실제로 바뀌었을 때만 알린다(같은 값 재그리기 0).
 * 메시지 스레드 한 곳에서만 부른다(잠금 없음).
 */
class TaskbarThemeTracker(initial: TaskbarTheme) {
    var current: TaskbarTheme = initial
        private set

    /** 레지스트리를 다시 읽은 횟수(진단·시험용). */
    var reads: Int = 0
        private set

    /** 바뀐 새 테마, 아니면 null. [read] 는 테마 설정 변경일 때만 부른다. */
    fun onSettingChange(area: String?, read: () -> TaskbarTheme): TaskbarTheme? {
        if (!isThemeArea(area)) return null
        reads++
        val next = read()
        if (next == current) return null
        current = next
        return next
    }

    companion object {
        const val IMMERSIVE_COLOR_SET = "ImmersiveColorSet"

        /** 설정 영역 이름은 레지스트리 키처럼 대소문자를 가리지 않는다. null(lParam 0) = 영역 미상 → 테마 아님. */
        fun isThemeArea(area: String?): Boolean = area != null && area.equals(IMMERSIVE_COLOR_SET, ignoreCase = true)
    }
}
