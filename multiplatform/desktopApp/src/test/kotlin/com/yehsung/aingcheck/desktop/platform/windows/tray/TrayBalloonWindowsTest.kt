// 원본: 없음(새 시험) — shell.md §5 Windows 러너 `TrayBalloonWindowsTest`(NIF_INFO 수정 성공) · §6 조정자 패치 3
//       (NIN_BALLOONUSERCLICK 0x405 듣기 · WM_SETTINGCHANGE("ImmersiveColorSet") 테마 듣기) · 핀 조정 ⑨ BalloonNotifier
//       · 방식은 runner/TrayWindowsTest·InstanceAndIdentityWindowsTest 그대로(@EnabledOnOs + 성공은 OS 의 BOOL·다른 프로세스로 잰다).
//       실제 풍선 클릭·화면에 보였나·집중 지원은 VM 묶음 ④(D-E14).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.sun.jna.Memory
import com.sun.jna.Pointer
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.io.File
import java.nio.file.Files
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

@EnabledOnOs(OS.WINDOWS)
class TrayBalloonWindowsTest {
    private val iconId = 9

    private fun icon(status: TrayIconStatus = TrayIconStatus.Off) =
        TrayIconRenderer.render(TrayIconSpec(status, redDot = false, theme = TaskbarTheme.DARK, sizePx = 24))

    @Test
    fun balloonModifyIsAcceptedByTheShellAndNeverRidesOnIconUpdates() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Balloon")).use { thread ->
            WindowsTrayHost(thread, iconId = iconId, retryWindowMillis = 20_000, themeReader = { TaskbarTheme.DARK }).use { tray ->
                // 아이콘이 셸에 없으면 풍선도 없다(부르지도 않는다).
                assertFalse(tray.showBalloon("아잉체크", "아이콘 전", NotifyKind.MESSAGE, respectQuietTime = false))
                assertEquals(0, tray.status().balloonCalls)

                tray.show(icon(), "aing-check 풍선 시험")
                RunnerSupport.waitUntil(20_000, "NIM_ADD(${tray.status()})") { tray.status().added }

                val ok = tray.showBalloon("아잉체크 시험", "풍선 본문", NotifyKind.MESSAGE, respectQuietTime = false)
                val st = tray.status()
                println("AINGCHECK-BALLOON ok=$ok status=$st")
                assertTrue(ok, "NIF_INFO NIM_MODIFY 가 FALSE: $st")
                assertEquals(true, st.lastBalloonOk)
                assertEquals(1, st.balloonCalls)
                assertEquals(0x10 or 0x40, st.lastBalloonFlags, "메시지는 NIF_INFO|NIF_REALTIME")
                assertEquals(0x04, st.lastBalloonInfoFlags)

                // 조용한 시간 존중(NIIF_RESPECT_QUIET_TIME): 새 사용자 첫 1시간 동안 셸이 무엇을 돌려주는지는 러너마다 다를 수 있다 — 기록만.
                val quiet = tray.showBalloon("아잉체크 시험", "조용한 시간 존중", NotifyKind.UPDATE, respectQuietTime = true)
                println("AINGCHECK-BALLOON quiet=$quiet flags=0x${Integer.toHexString(tray.status().lastBalloonInfoFlags)}")
                assertEquals(0x84, tray.status().lastBalloonInfoFlags)
                assertEquals(0x10, tray.status().lastBalloonFlags, "새 버전 안내는 실시간이 아니다")

                // 풍선 뒤 분 갱신: 아이콘 구조체에 NIF_INFO 가 없어야 같은 풍선이 분마다 다시 뜨지 않는다.
                tray.update(icon(TrayIconStatus.Working(60)), "aing-check 근무중 00:01")
                val after = tray.status()
                assertEquals(true, after.lastModifyOk, "풍선 뒤 아이콘 갱신 실패: $after")
                assertEquals(WindowsTrayHost.ICON_FLAGS, after.lastIconFlags)
                assertEquals(0, after.lastIconFlags and (0x10 or 0x40), "아이콘 갱신에 풍선 비트: $after")
                assertEquals(3, after.balloonCalls, "아이콘 갱신이 풍선 호출로 세어졌다")

                // 긴 글자는 szInfoTitle[64]·szInfo[256] 안으로 — 서로게이트 쌍을 반으로 가르지 않는다.
                assertTrue(tray.showBalloon("가".repeat(100), "😀".repeat(200), NotifyKind.POKE, respectQuietTime = false))
                val clipped = tray.status()
                assertEquals(63, clipped.lastBalloonTitle!!.length)
                val body = clipped.lastBalloonBody!!
                assertTrue(body.length <= 255 && body.length % 2 == 0, "본문 자르기 ${body.length}")
                assertFalse(Character.isHighSurrogate(body.last()))

                // 빈 본문은 '풍선 지우기' 명령이라 보내지 않는다.
                assertFalse(tray.showBalloon("제목", " ", NotifyKind.MESSAGE, respectQuietTime = false))
                assertEquals(4, tray.status().balloonCalls)

                tray.remove()
                assertFalse(tray.showBalloon("아잉체크", "삭제 뒤", NotifyKind.MESSAGE, respectQuietTime = false))
            }
        }
    }

    /** NIN_BALLOONUSERCLICK(0x405) → 마지막으로 띄운 종류로 처리기 한 번. 트레이 클릭 리스너로 새지 않는다. 다른 아이콘 id 는 무시. */
    @Test
    fun balloonUserClickReachesTheHandlerWithTheLastKindOnly() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.BalloonCb")).use { thread ->
            WindowsTrayHost(thread, iconId = iconId, retryWindowMillis = 20_000, themeReader = { TaskbarTheme.DARK }).use { tray ->
                val kinds = ArrayBlockingQueue<NotifyKind>(4)
                val clicks = AtomicInteger()
                tray.setOnBalloonClick { kinds.add(it) }
                tray.addClickListener { _, _, _ -> clicks.incrementAndGet() }
                fun post(event: Int, id: Int) {
                    val (w, l) = TrayCallbackDecoder.encode(event, id, 0, 0)
                    User32X.INSTANCE.PostMessageW(thread.hwnd, Win32.WM_APP_TRAY, WinDef.WPARAM(w), WinDef.LPARAM(l))
                }
                // 띄운 풍선이 없으면 클릭을 누구에게도 넘기지 않는다(nil 상대로 대화를 열지 않는다 — 규약 3 의 짝).
                post(TrayBalloonWin32.NIN_BALLOONUSERCLICK, iconId)
                assertNull(kinds.poll(300, TimeUnit.MILLISECONDS), "띄운 풍선이 없는데 처리기가 불렸다")

                tray.show(icon(), "aing-check 풍선 클릭 시험")
                RunnerSupport.waitUntil(20_000, "NIM_ADD") { tray.status().added }
                assertTrue(tray.showBalloon("아잉체크 시험", "콕!", NotifyKind.POKE, respectQuietTime = false), "${tray.status()}")

                post(TrayBalloonWin32.NIN_BALLOONUSERCLICK, iconId + 1)
                post(TrayBalloonWin32.NIN_BALLOONTIMEOUT, iconId)
                post(TrayBalloonWin32.NIN_BALLOONUSERCLICK, iconId)
                assertEquals(NotifyKind.POKE, kinds.poll(5, TimeUnit.SECONDS))
                assertNull(kinds.poll(300, TimeUnit.MILLISECONDS), "한 번 클릭에 두 번 / 다른 아이콘이 새었다")
                assertEquals(0, clicks.get(), "풍선 사건이 트레이 클릭으로 샜다")
            }
        }
    }

    /**
     * 다른 프로세스(자식 JVM)가 WM_SETTINGCHANGE 를 보낸다 — 실제 테마 변경처럼 lParam 글자가 프로세스 경계를 넘는다.
     * 레지스트리는 건드리지 않는다(합성 읽기). "ImmersiveColorSet" 일 때만 다시 읽고, 바뀌었을 때만 알린다.
     */
    @Test
    fun immersiveColorSetFromAnotherProcessRereadsTheThemeOnlyWhenItChanges() {
        Win32MessageThread.start(RunnerSupport.unique("AingCheck.Test.Theme")).use { thread ->
            val registry = AtomicReference(TaskbarTheme.DARK)
            WindowsTrayHost(thread, iconId = iconId, themeReader = { registry.get() }).use { tray ->
                val got = ArrayBlockingQueue<TaskbarTheme>(4)
                tray.addThemeListener { got.add(it) }
                assertEquals(TaskbarTheme.DARK, tray.currentTheme())
                val hwnd = Pointer.nativeValue(thread.hwnd.pointer).toString()

                registry.set(TaskbarTheme.LIGHT)
                assertEquals("sent=true", TraySettingChangeChild.run(hwnd, "Environment").trim())
                assertNull(got.poll(300, TimeUnit.MILLISECONDS), "테마 아닌 설정 변경에 알렸다")
                assertEquals(0, tray.status().themeReads)

                assertEquals("sent=true", TraySettingChangeChild.run(hwnd, "ImmersiveColorSet").trim())
                assertEquals(TaskbarTheme.LIGHT, got.poll(5, TimeUnit.SECONDS))
                assertEquals(TaskbarTheme.LIGHT, tray.currentTheme())
                assertEquals(1, tray.status().themeReads)

                assertEquals("sent=true", TraySettingChangeChild.run(hwnd, "ImmersiveColorSet").trim())
                assertNull(got.poll(300, TimeUnit.MILLISECONDS), "같은 테마인데 다시 알렸다")
                assertEquals(2, tray.status().themeReads)
            }
        }
    }
}

/**
 * 자식 JVM 으로 WM_SETTINGCHANGE 한 통을 보낸다(runner/RunnerSupport.runChild 와 같은 방식 — classpath 는 @인자 파일).
 * ChildProbe 는 runner 갈래 소유라 여기 진입점을 따로 둔다. 인자는 ASCII 만(Windows java 런처는 ANSI 코드 페이지).
 */
object TraySettingChangeChild {
    fun run(hwnd: String, area: String, timeoutSeconds: Long = 60): String {
        val javaExe = ProcessHandle.current().info().command().orElseThrow { IllegalStateException("java 경로를 모른다") }
        val argFile = Files.createTempFile("aingcheck-tray-child-cp", ".args")
        val cp = System.getProperty("java.class.path").replace("\\", "\\\\").replace("\"", "\\\"")
        Files.writeString(argFile, "-cp\n\"" + cp + "\"\n")
        try {
            val cmd = listOf(javaExe, "-Dstdout.encoding=UTF-8", "@" + argFile.toAbsolutePath(), TraySettingChangeChild::class.java.name, hwnd, area)
            val pb = ProcessBuilder(cmd)
            pb.redirectInput(ProcessBuilder.Redirect.from(File(if (File.separatorChar == '\\') "NUL" else "/dev/null")))
            val p = pb.start()
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                p.destroyForcibly()
                fail("자식 JVM 이 ${timeoutSeconds}초 안에 끝나지 않았다")
            }
            assertEquals(0, p.exitValue(), err)
            return out
        } finally {
            Files.deleteIfExists(argFile)
        }
    }

    /** 자식 진입점: SendMessageTimeoutW(hwnd, WM_SETTINGCHANGE, 0, L"<area>") — 셸이 테마를 바꿀 때 보내는 모양 그대로(대상만 한 창). */
    @JvmStatic
    fun main(args: Array<String>) {
        val hwnd = WinDef.HWND(Pointer(args[0].toLong()))
        val area = args[1]
        val text = Memory((area.length + 1) * 2L)
        text.setWideString(0, area)
        val result = WinDef.DWORDByReference()
        val smtoAbortIfHung = 0x0002
        val r = User32.INSTANCE.SendMessageTimeout(
            hwnd, TrayBalloonWin32.WM_SETTINGCHANGE, WinDef.WPARAM(0), WinDef.LPARAM(Pointer.nativeValue(text)),
            smtoAbortIfHung, 5_000, result,
        )
        println("sent=" + (r.toLong() != 0L))
    }
}
