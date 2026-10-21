package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.yehsung.aingcheck.desktop.platform.windows.identity.RegistryMachineIdentitySource
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsDeviceIdentity
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsInstallationIdentity
import com.yehsung.aingcheck.desktop.platform.windows.instance.InstanceSignal
import com.yehsung.aingcheck.desktop.platform.windows.instance.WindowsSingleInstanceGuard
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** G §2-3 W1-f ① 단일 실행 뮤텍스(같은 프로세스·다른 프로세스) + 첫 실행 깨우기 신호. */
@EnabledOnOs(OS.WINDOWS)
class SingleInstanceWindowsTest {
    private fun name() = "Local\\AingCheck.Test." + UUID.randomUUID()

    @Test
    fun secondGuardIsRefusedUntilTheFirstReleases() {
        val n = name()
        val a = WindowsSingleInstanceGuard(n)
        val b = WindowsSingleInstanceGuard(n)
        assertTrue(a.tryAcquire())
        assertEquals(0, a.lastError)
        assertFalse(b.tryAcquire(), "같은 이름을 둘이 잡았다")
        assertEquals(Win32.ERROR_ALREADY_EXISTS, b.lastError)
        assertTrue(a.tryAcquire(), "다시 물어도 쥔 쪽은 참(멱등)")
        a.release()
        assertTrue(b.tryAcquire(), "놓은 뒤에도 못 잡는다")
        b.release()
    }

    @Test
    fun anotherProcessSeesTheHeldMutexAndThenTheFreedOne() {
        val n = name()
        val mine = WindowsSingleInstanceGuard(n)
        assertTrue(mine.tryAcquire())
        val held = RunnerSupport.runChild(listOf("mutex", n))
        assertEquals("acquired=false err=183", held.stdout, held.stderr)
        mine.release()
        val freed = RunnerSupport.runChild(listOf("mutex", n))
        assertEquals("acquired=true err=0", freed.stdout, freed.stderr)
    }

    @Test
    fun secondProcessWakesTheFirstThroughItsHiddenWindow() {
        val cls = RunnerSupport.unique("AingCheck.Test.Wake")
        Win32MessageThread.start(cls).use { thread ->
            val woke = CountDownLatch(1)
            InstanceSignal.listen(thread) { woke.countDown() }.use {
                val r = RunnerSupport.runChild(listOf("signal", cls))
                assertEquals("sent=true", r.stdout, r.stderr)
                assertTrue(woke.await(5, TimeUnit.SECONDS), "첫 실행이 신호를 받지 못했다")
            }
        }
        // 짝: 그런 창이 없으면 보내지 못했다고 말한다(조용히 성공하지 않는다).
        assertEquals("sent=false", RunnerSupport.runChild(listOf("signal", RunnerSupport.unique("AingCheck.Test.Nobody"))).stdout)
    }
}

private inline fun <T> com.yehsung.aingcheck.core.foundation.platform.desktop.Registration.use(block: () -> T): T =
    try { block() } finally { close() }

/** G §2-3 W1-f ① UUIDv5 신원 — 두 번 계산해도 같은 값, 재료는 **다른 도구(reg.exe·whoami.exe)** 와 대조. */
@EnabledOnOs(OS.WINDOWS)
class IdentityWindowsTest {
    @field:TempDir
    lateinit var tmp: Path

    @Test
    fun registryAndTokenReadsMatchIndependentTools() {
        val src = RegistryMachineIdentitySource()
        val guid = src.machineGuid()
        val sid = src.userSid()
        assertNotNull(guid)
        assertNotNull(sid)
        val reg = RunnerSupport.runTool("reg.exe", "query", "HKLM\\SOFTWARE\\Microsoft\\Cryptography", "/v", "MachineGuid", "/reg:64")
        val regGuid = Regex("""MachineGuid\s+REG_SZ\s+(\S+)""").find(reg)?.groupValues?.get(1)
        assertEquals(regGuid, guid, "reg.exe 와 다르다: $reg")
        val who = RunnerSupport.runTool("whoami.exe", "/user", "/fo", "csv", "/nh")
        val whoSid = Regex("""(S-1-[0-9-]+)""").find(who)?.groupValues?.get(1)
        assertEquals(whoSid, sid, "whoami 와 다르다: $who")
    }

    @Test
    fun computedTwiceInFreshInstancesIsTheSameLowercaseV5AndWritesNoFallback() {
        val file = tmp.resolve("aing-check").resolve("installation-id")
        val a = WindowsInstallationIdentity(RegistryMachineIdentitySource(), file).resolve()
        val b = WindowsInstallationIdentity(RegistryMachineIdentitySource(), file).resolve()
        assertEquals(WindowsInstallationIdentity.Origin.MACHINE_DERIVED, a.origin)
        assertEquals(a, b)
        val id = a.installationId!!
        assertEquals(id.lowercase(), id)
        assertEquals(5, UUID.fromString(id).version())
        val src = RegistryMachineIdentitySource()
        assertEquals(WindowsDeviceIdentity.installationId(src.machineGuid()!!, src.userSid()!!), id)
        assertEquals("win:$id", WindowsDeviceIdentity.deviceId(id))
        assertFalse(Files.exists(file), "레지스트리를 읽었는데 무작위 폴백을 썼다")
        // 다른 JVM(자식)도 같은 재료에서 같은 값을 낸다 — 재실행·재설치 뒤에도 같은 기기라는 근거.
        val child = RunnerSupport.runChild(listOf("identity", tmp.resolve("child-id").toString()))
        assertEquals("MACHINE_DERIVED $id", child.stdout, child.stderr)
        println("AINGCHECK-IDENTITY origin=${a.origin} id-prefix=${id.take(8)}")
    }
}
