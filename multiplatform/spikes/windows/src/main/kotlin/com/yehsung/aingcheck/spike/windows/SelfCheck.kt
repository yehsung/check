package com.yehsung.aingcheck.spike.windows

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.ptr.IntByReference
import java.io.File
import java.security.MessageDigest
import javax.net.ssl.SSLContext

/**
 * `--selfcheck`(A §6-2): 창을 띄우지 않고 네트워크도 쓰지 않는다. 설치된 산출물이 "이번 빌드"인지 빌드 시각·SHA 로 판정하게 한다.
 * MSIX 안에서 부르면 패키지 신원·홈 폴더 읽기(D-E15 의 `.claude` 읽기 1차)·%LOCALAPPDATA% 쓰기 위치도 기록한다.
 */
object SelfCheck {
    const val RESOURCE = "/aingspike/marker.txt"
    const val MARKER = "aingspike-resource-marker-v1"
    private const val APPMODEL_ERROR_NO_PACKAGE = 15700

    private interface PackageApi : Library {
        fun GetCurrentPackageFullName(packageFullNameLength: IntByReference, packageFullName: CharArray?): Int
    }

    private interface CLib : Library {
        fun getpid(): Int
    }

    val isWindows: Boolean get() = System.getProperty("os.name").orEmpty().startsWith("Windows")

    fun run(readProbe: String?, writeProbe: String?): Pair<List<Check>, Map<String, Any?>> {
        val checks = mutableListOf<Check>()
        checks += buildStamp()
        checks += jna()
        checks += tls()
        checks += resource()
        if (readProbe != null) checks += readProbe(readProbe)
        if (writeProbe != null) checks += writeProbe(writeProbe)
        val env = linkedMapOf<String, Any?>(
            "javaRuntime" to System.getProperty("java.runtime.version"),
            "javaVendor" to System.getProperty("java.vendor"),
            "javaHome" to System.getProperty("java.home"),
            "osName" to System.getProperty("os.name"),
            "osArch" to System.getProperty("os.arch"),
            "userHome" to System.getProperty("user.home"),
            "localAppData" to System.getenv("LOCALAPPDATA"),
            "package" to packageName(),
            "headless" to System.getProperty("java.awt.headless"),
        )
        return checks to env
    }

    fun buildStamp(): Check {
        val ok = BuildInfo.BUILDTIME.isNotBlank() && BuildInfo.VERSION.isNotBlank()
        return Check("buildStamp", ok, detail = Verdict.buildInfoMap())
    }

    fun jna(): Check = try {
        val pidByJna = if (isWindows) {
            Kernel32X.INSTANCE.GetCurrentProcessId().toLong()
        } else {
            Native.load("c", CLib::class.java).getpid().toLong()
        }
        val pid = ProcessHandle.current().pid()
        Check(
            "jna", ok = pidByJna == pid,
            detail = linkedMapOf(
                "version" to Native.VERSION,
                "nativeVersion" to Native.VERSION_NATIVE,
                "pidByJna" to pidByJna,
                "pid" to pid,
                "jnidispatchPath" to System.getProperty("jnidispatch.path"),
                "jnaNoUnpack" to System.getProperty("jna.nounpack"),
                "jnaBootLibraryPath" to System.getProperty("jna.boot.library.path"),
            ),
        )
    } catch (e: Throwable) {
        Check("jna", ok = false, detail = mapOf("error" to e.toString()))
    }

    fun tls(): Check = try {
        val ctx = SSLContext.getDefault()
        val protocols = ctx.supportedSSLParameters.protocols.toList()
        Check(
            "tls", ok = "TLSv1.3" in protocols || "TLSv1.2" in protocols,
            detail = linkedMapOf("provider" to ctx.provider.name, "protocols" to protocols),
        )
    } catch (e: Throwable) {
        Check("tls", ok = false, detail = mapOf("error" to e.toString()))
    }

    fun resource(): Check {
        val text = SelfCheck::class.java.getResourceAsStream(RESOURCE)?.use { it.readBytes().toString(Charsets.UTF_8).trim() }
        return Check("resource", ok = text == MARKER, detail = linkedMapOf("path" to RESOURCE, "found" to (text != null)))
    }

    fun readProbe(path: String): Check = try {
        val f = File(path)
        val bytes = f.readBytes()
        Check(
            "readProbe", ok = true,
            detail = linkedMapOf("path" to path, "bytes" to bytes.size, "sha256" to sha256(bytes)),
        )
    } catch (e: Throwable) {
        Check("readProbe", ok = false, detail = linkedMapOf("path" to path, "error" to e.toString()))
    }

    fun writeProbe(path: String): Check = try {
        val f = File(path)
        f.absoluteFile.parentFile?.mkdirs()
        val payload = "aingspike write probe ${BuildInfo.BUILDTIME}"
        f.writeText(payload)
        val back = f.readText()
        Check("writeProbe", ok = back == payload, detail = linkedMapOf("path" to path, "canonical" to f.canonicalPath))
    } catch (e: Throwable) {
        Check("writeProbe", ok = false, detail = linkedMapOf("path" to path, "error" to e.toString()))
    }

    /** MSIX 안이면 패키지 전체 이름, 밖이면 "none", Windows 가 아니면 null. */
    fun packageName(): String? {
        if (!isWindows) return null
        return try {
            val api = Native.load("kernel32", PackageApi::class.java)
            val len = IntByReference(0)
            val first = api.GetCurrentPackageFullName(len, null)
            if (first == APPMODEL_ERROR_NO_PACKAGE) return "none"
            val buf = CharArray(maxOf(len.value, 1))
            val rc = api.GetCurrentPackageFullName(len, buf)
            if (rc == 0) String(buf, 0, maxOf(0, len.value - 1)) else "error:$rc"
        } catch (e: Throwable) {
            "error:$e"
        }
    }

    fun sha256(b: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
}
