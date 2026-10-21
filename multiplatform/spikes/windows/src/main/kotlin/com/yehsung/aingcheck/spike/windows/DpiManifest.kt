package com.yehsung.aingcheck.spike.windows

import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

/**
 * D-E22: 런처 manifest 의 DPI 인식 수준.
 * - `dpiAwareness`(2016 네임스페이스)가 있으면 그것이 이긴다. 목록이면 OS 가 아는 **첫 값**이 쓰인다(Windows 10 1703+ 는 넷 다 안다).
 * - 없으면 `dpiAware`(2005): "true/pm"·"per monitor" = PerMonitor(v1), "true" = System.
 */
data class DpiInfo(
    val dpiAware: String?,
    val dpiAwareness: String?,
    val effective: String,
) {
    val perMonitorV2: Boolean get() = effective == "PerMonitorV2"
    fun toMap(): Map<String, Any?> =
        linkedMapOf("dpiAware" to dpiAware, "dpiAwareness" to dpiAwareness, "effective" to effective, "perMonitorV2" to perMonitorV2)
}

object DpiManifest {
    private val known = linkedMapOf(
        "permonitorv2" to "PerMonitorV2",
        "permonitor" to "PerMonitor",
        "system" to "System",
        "unaware" to "Unaware",
    )

    fun parse(xml: ByteArray): DpiInfo {
        val f = DocumentBuilderFactory.newInstance()
        f.isNamespaceAware = true
        f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        f.isXIncludeAware = false
        f.isExpandEntityReferences = false
        val doc = f.newDocumentBuilder().parse(ByteArrayInputStream(stripBom(xml)))
        var dpiAware: String? = null
        var dpiAwareness: String? = null
        val all = doc.getElementsByTagNameNS("*", "*")
        for (i in 0 until all.length) {
            val el = all.item(i) as Element
            val local = el.localName ?: el.tagName.substringAfter(':')
            when (local) {
                "dpiAware" -> if (dpiAware == null) dpiAware = el.textContent.trim()
                "dpiAwareness" -> if (dpiAwareness == null) dpiAwareness = el.textContent.trim()
            }
        }
        return DpiInfo(dpiAware, dpiAwareness, effective(dpiAware, dpiAwareness))
    }

    fun effective(dpiAware: String?, dpiAwareness: String?): String {
        if (!dpiAwareness.isNullOrBlank()) {
            val first = dpiAwareness.split(',').map { it.trim().lowercase() }.firstOrNull { it in known }
            if (first != null) return known.getValue(first)
        }
        return when (dpiAware?.trim()?.lowercase()) {
            "true/pm", "per monitor" -> "PerMonitor"
            "true" -> "System"
            else -> "Unaware"
        }
    }

    private fun stripBom(b: ByteArray): ByteArray =
        if (b.size >= 3 && b[0] == 0xEF.toByte() && b[1] == 0xBB.toByte() && b[2] == 0xBF.toByte()) b.copyOfRange(3, b.size) else b
}
