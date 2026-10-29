// 원본: 없음(새 시험) — 핀 shellapi 조정 ⑨(BalloonNotifier) · shell.md §6 조정자 패치 3 · W-3 #6(풍선 = 토스트 표면)
//       · learn.microsoft.com NOTIFYICONDATAW·Shell_NotifyIcon(상수 값은 shellapi.h·winuser.h 에서 손으로 옮겨 적었다 — 코드 상수를 기대값에 쓰지 않는다)
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** 풍선 계획·풍선 콜백 풀기·테마 거르기 — 맥 JVM 에서 JNA 없이 잰다. Shell_NotifyIcon 실호출은 TrayBalloonWindowsTest(러너). */
class TrayBalloonPlanTest {
    @Test
    fun win32ValuesMatchTheHeaders() {
        assertEquals(0x00000010, TrayBalloonWin32.NIF_INFO)
        assertEquals(0x00000040, TrayBalloonWin32.NIF_REALTIME)
        assertEquals(0x00000004, TrayBalloonWin32.NIIF_USER)
        assertEquals(0x00000080, TrayBalloonWin32.NIIF_RESPECT_QUIET_TIME)
        assertEquals(0x402, TrayBalloonWin32.NIN_BALLOONSHOW)
        assertEquals(0x403, TrayBalloonWin32.NIN_BALLOONHIDE)
        assertEquals(0x404, TrayBalloonWin32.NIN_BALLOONTIMEOUT)
        assertEquals(0x405, TrayBalloonWin32.NIN_BALLOONUSERCLICK)
        assertEquals(0x1A, TrayBalloonWin32.WM_SETTINGCHANGE)
        // szInfoTitle[64]·szInfo[256] − 끝 NUL.
        assertEquals(63, TrayBalloonWin32.MAX_TITLE_CHARS)
        assertEquals(255, TrayBalloonWin32.MAX_BODY_CHARS)
    }

    /** 4종 × 조용한 시간 2 = 8칸 전수. 기대 비트는 손으로 적는다(0x10 = NIF_INFO, 0x40 = NIF_REALTIME, 0x04 = NIIF_USER, 0x80 = 조용한 시간). */
    @Test
    fun flagTableAllKindsTimesQuietTime() {
        val expected = mapOf(
            (NotifyKind.MESSAGE to false) to (0x50 to 0x04),
            (NotifyKind.MESSAGE to true) to (0x50 to 0x84),
            (NotifyKind.POKE to false) to (0x50 to 0x04),
            (NotifyKind.POKE to true) to (0x50 to 0x84),
            (NotifyKind.DUEL_INVITE to false) to (0x50 to 0x04),
            (NotifyKind.DUEL_INVITE to true) to (0x50 to 0x84),
            // 새 버전 안내만 실시간이 아니다(늦게 떠도 참).
            (NotifyKind.UPDATE to false) to (0x10 to 0x04),
            (NotifyKind.UPDATE to true) to (0x10 to 0x84),
        )
        assertEquals(NotifyKind.entries.size * 2, expected.size, "새 NotifyKind 가 표에 없다")
        for ((key, flags) in expected) {
            val (kind, quiet) = key
            val plan = assertNotNull(BalloonPlanner.plan("제목", "본문", kind, quiet), "$kind/$quiet")
            assertEquals(flags.first, plan.uFlags, "uFlags $kind/$quiet")
            assertEquals(flags.second, plan.dwInfoFlags, "dwInfoFlags $kind/$quiet")
        }
    }

    /** 풍선 갱신은 아이콘·툴팁·콜백 비트를 건드리지 않고, 아이콘 갱신은 풍선 비트를 갖지 않는다(분마다 같은 풍선이 다시 뜨는 결함의 짝). */
    @Test
    fun balloonAndIconFlagsAreDisjoint() {
        val iconBits = 0x01 or 0x02 or 0x04 or 0x80 // NIF_MESSAGE·ICON·TIP·SHOWTIP
        val balloonBits = 0x10 or 0x40
        assertEquals(iconBits, WindowsTrayHost.ICON_FLAGS)
        for (kind in NotifyKind.entries) for (quiet in listOf(false, true)) {
            val plan = BalloonPlanner.plan("t", "b", kind, quiet)!!
            assertEquals(0, plan.uFlags and iconBits, "풍선이 아이콘 비트를 켠다: $kind")
        }
        assertEquals(0, WindowsTrayHost.ICON_FLAGS and balloonBits, "아이콘 갱신이 풍선 비트를 켠다")
    }

    /** 빈 szInfo + NIF_INFO = '떠 있는 풍선 지우기'(문서) — 빈 본문은 띄우지 않는다. 글자는 여기서 자르지 않는다(구조체에 넣을 때 한 곳). */
    @Test
    fun blankBodyIsNotABalloonAndTextIsPassedThrough() {
        assertNull(BalloonPlanner.plan("제목", "", NotifyKind.MESSAGE, false))
        assertNull(BalloonPlanner.plan("제목", "  \n", NotifyKind.POKE, true))
        val long = "가".repeat(400)
        val plan = BalloonPlanner.plan("😀".repeat(40), long, NotifyKind.MESSAGE, false)!!
        assertEquals(long, plan.body)
        assertEquals("😀".repeat(40), plan.title)
    }

    /** lParam 은 손으로 짠다: HIWORD = 아이콘 id, LOWORD = 사건. */
    @Test
    fun balloonCallbacksDecodeAndNeverLeakIntoClicks() {
        assertEquals(BalloonEvent(BalloonEventKind.USER_CLICKED, 7), TrayCallbackDecoder.decodeBalloon(0x0007_0405L))
        assertEquals(BalloonEvent(BalloonEventKind.SHOWN, 1), TrayCallbackDecoder.decodeBalloon(0x0001_0402L))
        assertEquals(BalloonEvent(BalloonEventKind.HIDDEN, 1), TrayCallbackDecoder.decodeBalloon(0x0001_0403L))
        assertEquals(BalloonEvent(BalloonEventKind.TIMED_OUT, 2), TrayCallbackDecoder.decodeBalloon(0x0002_0404L))
        // 풍선 사건은 트레이 클릭이 아니다(풍선 클릭이 플라이아웃 '홈' 열기로 새면 안 된다 — 규약 3: 보낸이 대화로).
        for (ev in listOf(0x402L, 0x403L, 0x404L, 0x405L)) {
            assertNull(TrayCallbackDecoder.decode(wParam = 0x0010_0010L, lParam = 0x0007_0000L or ev), "클릭으로 샜다: 0x${ev.toString(16)}")
        }
        // 짝: 클릭 사건은 풍선이 아니다.
        for (ev in listOf(0x400L, 0x401L, 0x7BL, 0x203L)) {
            assertNull(TrayCallbackDecoder.decodeBalloon(0x0007_0000L or ev), "풍선으로 샜다: 0x${ev.toString(16)}")
        }
        assertEquals(TrayClick.PRIMARY, TrayCallbackDecoder.decode(0L, 0x0007_0400L)?.click)
    }

    @Test
    fun themeTrackerRereadsOnlyOnImmersiveColorSetAndReportsOnlyChanges() {
        var registry = TaskbarTheme.DARK
        var reads = 0
        val read = { reads++; registry }
        val t = TaskbarThemeTracker(TaskbarTheme.DARK)
        // 다른 설정 변경·영역 미상은 레지스트리를 읽지도 않는다.
        for (area in listOf(null, "", "Environment", "Policy", "intl", "ImmersiveColorSetX")) {
            registry = TaskbarTheme.LIGHT
            assertNull(t.onSettingChange(area, read), "테마 아닌 '$area' 에서 알렸다")
        }
        assertEquals(0, reads)
        assertEquals(0, t.reads)
        assertEquals(TaskbarTheme.DARK, t.current)
        // 테마 변경: 읽고, 바뀌었으면 알린다.
        assertEquals(TaskbarTheme.LIGHT, t.onSettingChange("ImmersiveColorSet", read))
        assertEquals(TaskbarTheme.LIGHT, t.current)
        // 같은 값이면 읽되 알리지 않는다(같은 아이콘 다시 그리기 0).
        assertNull(t.onSettingChange("ImmersiveColorSet", read))
        // 대소문자 무시.
        registry = TaskbarTheme.DARK
        assertEquals(TaskbarTheme.DARK, t.onSettingChange("immersivecolorset", read))
        assertEquals(3, reads)
        assertEquals(3, t.reads)
    }
}
