package com.yehsung.aingcheck.spike.windows

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DpiManifestTest {
    private fun manifest(windowsSettings: String) = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
          <application xmlns="urn:schemas-microsoft-com:asm.v3">
            <windowsSettings>
              $windowsSettings
            </windowsSettings>
          </application>
        </assembly>
    """.trimIndent().toByteArray()

    private val awareV1 = """<dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/PM</dpiAware>"""
    private fun awareness(v: String) = """<dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">$v</dpiAwareness>"""

    @Test
    fun jdkStyleManifestIsPerMonitorV2() {
        val info = DpiManifest.parse(manifest(awareV1 + awareness("PerMonitorV2")))
        assertEquals("PerMonitorV2", info.effective)
        assertTrue(info.perMonitorV2)
        assertEquals("true/PM", info.dpiAware)
    }

    @Test
    fun firstRecognisedAwarenessWins() {
        assertFalse(DpiManifest.parse(manifest(awareness("PerMonitor, PerMonitorV2"))).perMonitorV2)
        assertEquals("PerMonitor", DpiManifest.parse(manifest(awareness("PerMonitor, PerMonitorV2"))).effective)
        assertTrue(DpiManifest.parse(manifest(awareness("bogus, permonitorv2 ,PerMonitor"))).perMonitorV2)
    }

    @Test
    fun legacyDpiAwareOnly() {
        assertEquals("PerMonitor", DpiManifest.parse(manifest(awareV1)).effective)
        val sys = """<dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>"""
        assertEquals("System", DpiManifest.parse(manifest(sys)).effective)
        assertEquals("Unaware", DpiManifest.parse(manifest("")).effective)
    }

    @Test
    fun withBomAndNoAwarenessIsUnaware() {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + manifest("")
        assertEquals("Unaware", DpiManifest.parse(bom).effective)
    }

    @Test
    fun rejectsDoctype() {
        val evil = """<?xml version="1.0"?><!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/hosts">]><a>&x;</a>""".toByteArray()
        assertFailsWith<Exception> { DpiManifest.parse(evil) }
    }
}
