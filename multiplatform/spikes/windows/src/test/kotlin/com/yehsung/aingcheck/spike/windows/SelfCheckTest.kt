package com.yehsung.aingcheck.spike.windows

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** selfcheck 는 어느 OS 에서나 돈다(JNA 는 Windows 면 kernel32, 아니면 libc 로 pid 를 대조한다). */
class SelfCheckTest {
    @Test
    fun selfcheckPassesWithoutProbesAndMeasuresPid() {
        val (checks, env) = SelfCheck.run(null, null)
        val byId = checks.associateBy { it.id }
        assertEquals(setOf("buildStamp", "jna", "tls", "resource"), byId.keys)
        assertTrue(byId.getValue("jna").ok, byId.getValue("jna").detail.toString())
        assertEquals(byId.getValue("jna").detail["pid"], byId.getValue("jna").detail["pidByJna"])
        assertTrue(byId.getValue("resource").ok)
        assertTrue(byId.getValue("tls").ok)
        assertEquals(0, Verdict.exitCode(checks))
        assertEquals(System.getProperty("os.arch"), env["osArch"])
    }

    @Test
    fun readProbeFailsOnMissingFileAndHashesExistingOne() {
        val dir = Files.createTempDirectory("aingspike-probe").toFile()
        try {
            val missing = SelfCheck.readProbe(dir.resolve("absent.txt").path)
            assertFalse(missing.ok)
            val f = dir.resolve("present.txt").apply { writeText("abc") }
            val present = SelfCheck.readProbe(f.path)
            assertTrue(present.ok)
            assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", present.detail["sha256"])
            val (checks, _) = SelfCheck.run(dir.resolve("absent.txt").path, null)
            assertEquals(1, Verdict.exitCode(checks))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun writeProbeRoundTrips() {
        val dir = Files.createTempDirectory("aingspike-write").toFile()
        try {
            val c = SelfCheck.writeProbe(dir.resolve("sub/w.txt").path)
            assertTrue(c.ok, c.detail.toString())
        } finally {
            dir.deleteRecursively()
        }
    }
}
