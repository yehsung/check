// 원본: 없음(새 시험 도우미) — 설계 D§2-5·§5-1·§6(러너에서 실제 OS 로 재는 것) · W0-e 탐침 Smoke(자식 JVM·SendInput)
//       · R2 검증 지적(신원 재계산 단언이 같은 함수·같은 입력이었다 → PowerShell 로 다른 구현의 기대값)
package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.yehsung.aingcheck.desktop.platform.windows.identity.Uuid5
import com.yehsung.aingcheck.desktop.platform.windows.instance.InstanceSignal
import com.yehsung.aingcheck.desktop.platform.windows.instance.WindowsSingleInstanceGuard
import java.io.File
import java.nio.file.Files
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * Windows 러너 시험 도우미.
 * - 실제 입력 주입(SendInput)은 **사용자 화면에 키·마우스를 보낸다** — CI 러너(GITHUB_ACTIONS=true)나 시험 전용 VM
 *   (AINGCHECK_ALLOW_INPUT_INJECTION=1)에서만 한다. 사람이 쓰는 PC 에서 이 시험이 돌면 그 몇 개만 건너뛴다.
 * - 다른 프로세스가 필요한 시험(뮤텍스·활성화 신호·JNA 풀기)은 같은 JDK·같은 classpath 로 자식 JVM 을 띄운다.
 */
object RunnerSupport {
    fun inputInjectionAllowed(): Boolean =
        System.getenv("GITHUB_ACTIONS") == "true" || System.getenv("AINGCHECK_ALLOW_INPUT_INJECTION") == "1"

    fun unique(prefix: String): String = "$prefix.${ProcessHandle.current().pid()}.${System.nanoTime()}"

    fun waitUntil(timeoutMillis: Long, what: String, cond: () -> Boolean) {
        val deadline = System.nanoTime() + timeoutMillis * 1_000_000
        while (System.nanoTime() < deadline) {
            if (cond()) return
            Thread.sleep(50)
        }
        if (!cond()) fail("${timeoutMillis}ms 안에 일어나지 않았다: $what")
    }

    data class ChildResult(val exitCode: Int, val stdout: String, val stderr: String)

    /**
     * 같은 JDK·classpath 로 [ChildProbe] 를 띄운다. classpath 는 @인자 파일로 넘긴다 — Windows 는 명령줄과 환경 변수 하나가
     * 32K 자에서 잘리는데 데스크톱 시험 classpath(Compose·Ktor·skiko jar 수십 개)는 그 근처다. 인자 파일 안에서는 따옴표 안
     * 역슬래시가 이스케이프 문자라 두 번 쓴다(java 런처 @argfiles 규칙).
     */
    fun runChild(args: List<String>, jvmArgs: List<String> = emptyList(), timeoutSeconds: Long = 60): ChildResult {
        val javaExe = ProcessHandle.current().info().command().orElseThrow { IllegalStateException("java 경로를 모른다") }
        val argFile = Files.createTempFile("aingcheck-child-cp", ".args")
        val cp = System.getProperty("java.class.path").replace("\\", "\\\\").replace("\"", "\\\"")
        Files.writeString(argFile, "-cp\n\"" + cp + "\"\n")
        try {
            return runChildWith(javaExe, listOf("@" + argFile.toAbsolutePath()), args, jvmArgs, timeoutSeconds)
        } finally {
            Files.deleteIfExists(argFile)
        }
    }

    private fun runChildWith(javaExe: String, cpArgs: List<String>, args: List<String>, jvmArgs: List<String>, timeoutSeconds: Long): ChildResult {
        val cmd = listOf(javaExe, "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8") + cpArgs + jvmArgs + listOf(ChildProbe::class.java.name) + args
        val pb = ProcessBuilder(cmd)
        pb.redirectInput(ProcessBuilder.Redirect.from(File(if (File.separatorChar == '\\') "NUL" else "/dev/null")))
        val p = pb.start()
        val out = p.inputStream.bufferedReader().readText()
        val err = p.errorStream.bufferedReader().readText()
        if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
            p.destroyForcibly()
            fail("자식 JVM 이 ${timeoutSeconds}초 안에 끝나지 않았다: $args")
        }
        return ChildResult(p.exitValue(), out.trim(), err.trim())
    }

    /**
     * UUIDv5(RFC 9562 §5.5)를 **다른 구현**으로 계산한다: Windows PowerShell 5.1 의 .NET SHA1(모든 Windows 10/11·러너 2종에 있다).
     * 우리 Kotlin [com.yehsung.aingcheck.desktop.platform.windows.identity.Uuid5] 와 기대값을 나누려는 것이다(기억 comparison-baseline-must-differ).
     * 값은 스크립트 글에 끼워 넣지 않고 환경 변수로만 넘긴다(기억 shell-values-go-as-argv-not-interpolation). 스크립트는 ASCII 만 쓴다.
     */
    fun uuid5ViaPowerShell(namespaceHex: String, name: String): String {
        val script = listOf(
            "\$ErrorActionPreference = 'Stop'",
            "\$ProgressPreference = 'SilentlyContinue'",
            "\$hex = \$env:AINGCHECK_NS_HEX",
            "if (\$hex -notmatch '^[0-9a-fA-F]{32}\$') { throw 'namespace hex' }",
            "\$ns = New-Object 'byte[]' 16",
            "for (\$i = 0; \$i -lt 16; \$i++) { \$ns[\$i] = [Convert]::ToByte(\$hex.Substring(\$i * 2, 2), 16) }",
            "\$nb = [Text.Encoding]::UTF8.GetBytes(\$env:AINGCHECK_NAME)",
            "\$buf = New-Object 'byte[]' (16 + \$nb.Length)",
            "[Array]::Copy(\$ns, 0, \$buf, 0, 16)",
            "[Array]::Copy(\$nb, 0, \$buf, 16, \$nb.Length)",
            "\$h = [Security.Cryptography.SHA1]::Create().ComputeHash(\$buf)",
            "\$h[6] = [byte]((\$h[6] -band 0x0F) -bor 0x50)",
            "\$h[8] = [byte]((\$h[8] -band 0x3F) -bor 0x80)",
            "\$s = (\$h[0..15] | ForEach-Object { \$_.ToString('x2') }) -join ''",
            "[Console]::Out.Write(\$s.Substring(0, 8) + '-' + \$s.Substring(8, 4) + '-' + \$s.Substring(12, 4) + '-' + \$s.Substring(16, 4) + '-' + \$s.Substring(20, 12))",
        ).joinToString("\n")
        val encoded = Base64.getEncoder().encodeToString(script.toByteArray(Charsets.UTF_16LE))
        val pb = ProcessBuilder("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded)
        pb.environment()["AINGCHECK_NS_HEX"] = namespaceHex
        pb.environment()["AINGCHECK_NAME"] = name
        pb.redirectInput(ProcessBuilder.Redirect.from(File("NUL")))
        pb.redirectError(ProcessBuilder.Redirect.DISCARD) // 진행 기록(CLIXML)이 표준 오류로 섞여 나올 수 있다 — 값은 표준 출력만 본다
        val p = pb.start()
        val out = p.inputStream.bufferedReader(Charsets.US_ASCII).readText()
        if (!p.waitFor(60, TimeUnit.SECONDS)) {
            p.destroyForcibly()
            fail("powershell.exe 가 60초 안에 끝나지 않았다")
        }
        assertEquals(0, p.exitValue(), "powershell.exe 종료 코드 · $out")
        return out.trim()
    }

    /** 외부 도구(reg.exe·whoami.exe)를 돌려 표준 출력을 받는다 — 우리 JNA 읽기와 다른 길로 같은 사실을 잰다. */
    fun runTool(vararg cmd: String): String {
        val p = ProcessBuilder(*cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader(Charsets.UTF_8).readText()
        if (!p.waitFor(30, TimeUnit.SECONDS)) {
            p.destroyForcibly()
            fail("${cmd.toList()} 가 30초 안에 끝나지 않았다")
        }
        assertEquals(0, p.exitValue(), "${cmd.toList()} 종료 코드 · $out")
        return out
    }
}

/** 실제 입력 주입(SendInput). 하나씩 보낸다 — 배열은 연속 메모리여야 해서 하나씩이 단순하다. 넣은 건수를 돌려준다. */
object Inject {
    const val VK_SHIFT = 0x10
    const val VK_CONTROL = 0x11
    const val VK_MENU = 0x12
    const val VK_SPACE = 0x20
    const val VK_F24 = 0x87
    private const val KEYEVENTF_KEYUP = 0x0002
    private const val MOUSEEVENTF_MOVE = 0x0001
    private const val MOUSEEVENTF_XDOWN = 0x0080
    private const val MOUSEEVENTF_XUP = 0x0100
    private const val MOUSEEVENTF_WHEEL = 0x0800
    private const val XBUTTON1 = 0x0001

    private fun send(input: WinUser.INPUT): Int =
        User32.INSTANCE.SendInput(WinDef.DWORD(1), arrayOf(input), input.size()).toInt()

    fun key(vk: Int, up: Boolean): Int {
        val i = WinUser.INPUT()
        i.type = WinDef.DWORD(WinUser.INPUT.INPUT_KEYBOARD.toLong())
        i.input.setType("ki")
        i.input.ki.wVk = WinDef.WORD(vk.toLong())
        i.input.ki.dwFlags = WinDef.DWORD(if (up) KEYEVENTF_KEYUP.toLong() else 0L)
        return send(i)
    }

    private fun mouse(flags: Int, dx: Int = 0, dy: Int = 0, data: Int = 0): Int {
        val i = WinUser.INPUT()
        i.type = WinDef.DWORD(WinUser.INPUT.INPUT_MOUSE.toLong())
        i.input.setType("mi")
        i.input.mi.dx = WinDef.LONG(dx.toLong())
        i.input.mi.dy = WinDef.LONG(dy.toLong())
        i.input.mi.mouseData = WinDef.DWORD(data.toLong() and 0xFFFFFFFFL)
        i.input.mi.dwFlags = WinDef.DWORD(flags.toLong())
        return send(i)
    }

    fun mouseMove(dx: Int, dy: Int) = mouse(MOUSEEVENTF_MOVE, dx, dy)
    fun wheel(delta: Int) = mouse(MOUSEEVENTF_WHEEL, data = delta)
    fun xButton(up: Boolean) = mouse(if (up) MOUSEEVENTF_XUP else MOUSEEVENTF_XDOWN, data = XBUTTON1)
}

/** 자식 JVM 진입점(시험 classpath 안). */
object ChildProbe {
    @JvmStatic
    fun main(args: Array<String>) {
        when (args.firstOrNull()) {
            "echo" -> println(args.drop(1).joinToString(" "))
            "uuid5" -> println(Uuid5.nameBased(Uuid5.NAMESPACE_DNS, args[1]))
            "mutex" -> {
                val g = WindowsSingleInstanceGuard(args[1])
                val ok = g.tryAcquire()
                println("acquired=$ok err=${g.lastError}")
                g.release()
            }
            "signal" -> println("sent=" + InstanceSignal.activateExisting(args[1]))
            "identity" -> {
                val r = com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsInstallationIdentity(
                    com.yehsung.aingcheck.desktop.platform.windows.identity.RegistryMachineIdentitySource(),
                    java.nio.file.Path.of(args[1]),
                ).resolve()
                println("${r.origin} ${r.installationId}")
            }
            "jna" -> {
                // JNA 가 실제로 떴는지: 포인터 크기와 Win32 호출 하나.
                println("pointer=" + com.sun.jna.Native.POINTER_SIZE)
                println("tick=" + (com.sun.jna.platform.win32.Kernel32.INSTANCE.GetTickCount().toLong() and 0xFFFFFFFFL))
            }
            else -> {
                System.err.println("모르는 명령: ${args.toList()}")
                kotlin.system.exitProcess(64)
            }
        }
    }
}
