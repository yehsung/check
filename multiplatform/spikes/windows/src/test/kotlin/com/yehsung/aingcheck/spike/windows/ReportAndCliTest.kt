package com.yehsung.aingcheck.spike.windows

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ReportAndCliTest {
    @Test
    fun jsonEscapesAndKeepsOrder() {
        val s = Json.encode(linkedMapOf("b" to "a\"b\\c\n\u0001한", "a" to listOf(1, true, null), "c" to 2.5))
        assertEquals("""{"b":"a\"b\\c\n\u0001한","a":[1,true,null],"c":2.5}""", s)
    }

    @Test
    fun checkEncodesAsObject() {
        val s = Json.encode(Check("x", ok = false, required = false, detail = mapOf("k" to 1)))
        assertEquals("""{"id":"x","ok":false,"required":false,"detail":{"k":1}}""", s)
    }

    @Test
    fun verdictNeedsAtLeastOneRequiredCheck() {
        assertEquals(1, Verdict.exitCode(emptyList()))
        assertEquals(1, Verdict.exitCode(listOf(Check("info", ok = true, required = false))))
        assertEquals(0, Verdict.exitCode(listOf(Check("a", true), Check("info", ok = false, required = false))))
        assertEquals(1, Verdict.exitCode(listOf(Check("a", true), Check("b", false))))
    }

    @Test
    fun cliParsesSelfcheckAliasAndRejectsUnknown() {
        val p = Cli.parse(listOf("--selfcheck=C:\\out\\s.json", "--read-probe=C:\\x.txt"))
        assertEquals("selfcheck", p.command)
        assertEquals("C:\\out\\s.json", p.one("out"))
        assertEquals("C:\\x.txt", p.one("read-probe"))
        val m = Cli.parse(listOf("manifest", "--exe=a.exe", "--exe=b.exe", "--require-pmv2"))
        assertEquals(listOf("a.exe", "b.exe"), m.all("exe"))
        assertTrue("require-pmv2" in m.flags)
        assertFailsWith<Cli.UsageException> { Cli.parse(emptyList()) }
        assertFailsWith<Cli.UsageException> { Cli.parse(listOf("bogus")) }
        assertFailsWith<Cli.UsageException> { Cli.parse(listOf("smoke", "--exe=a")) }
        assertFailsWith<Cli.UsageException> { Cli.parse(listOf("smoke", "positional")) }
        assertFailsWith<Cli.UsageException> { Cli.parse(listOf("manifest", "--exe=")) }
        assertFailsWith<Cli.UsageException> { Cli.run(listOf("manifest")) }
    }

    @Test
    fun manifestCheckRequiresPmv2OnlyWhenAsked() {
        val dir = Files.createTempDirectory("aingspike-pe").toFile()
        try {
            val xml = """<assembly xmlns="urn:schemas-microsoft-com:asm.v1"><application><windowsSettings>
                <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
                </windowsSettings></application></assembly>""".toByteArray()
            val exe = File(dir, "sys.exe").apply { writeBytes(PeResourcesTest().buildPe(listOf(PeResourcesTest.Res(24, 1, xml)))) }
            val relaxed = Cli.manifestCheck(exe, requirePmv2 = false)
            val strict = Cli.manifestCheck(exe, requirePmv2 = true)
            assertTrue(relaxed.ok)
            assertEquals("System", relaxed.detail["effective"])
            assertEquals(false, strict.ok)
            val missing = Cli.manifestCheck(File(dir, "nope.exe"), requirePmv2 = false)
            assertEquals(false, missing.ok)
        } finally {
            dir.deleteRecursively()
        }
    }
}
