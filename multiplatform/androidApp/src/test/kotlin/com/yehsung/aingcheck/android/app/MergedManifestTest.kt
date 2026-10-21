// W1-g 완료 기준 ②⑥ · §8-12(E-U16 launchMode): **병합 매니페스트**를 읽어 단언한다(라이브러리가 더한 것까지 본다).
// 자리: 앱 APK 에 들어가는 debug 병합 매니페스트(processDebugMainManifest 출력 — 호스트 시험 매니페스트의 입력이라 시험 전에 늘 있다).
// 호스트 시험용 매니페스트(test_config.properties 의 android_merged_manifest)는 쓰지 않는다: androidx.test·Roborazzi 가 시험 전용
// Activity·REORDER_TASKS 를 더해 앱의 실제 모양이 아니다(실측). 자리를 못 찾으면 빨강이다(건너뛰지 않는다).
package com.yehsung.aingcheck.android.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import java.util.Properties
import javax.xml.parsers.DocumentBuilderFactory

class MergedManifestTest {
    private val ns = "http://schemas.android.com/apk/res/android"

    private val manifest: Element by lazy {
        // 시험 작업의 작업 디렉터리 = 모듈 디렉터리(Gradle 기본). 기준선으로 같은 자리의 호스트 시험 매니페스트도 있어야 한다.
        val props = Properties().apply {
            val stream = MergedManifestTest::class.java.classLoader!!.getResourceAsStream("com/android/tools/test_config.properties")
            assertNotNull("test_config.properties 가 없다 — isIncludeAndroidResources 가 꺼졌다", stream)
            stream!!.use { load(it) }
        }
        assertTrue(File(props.getProperty("android_merged_manifest")).isFile)
        val file = File(APP_MERGED_MANIFEST)
        assertTrue("앱 병합 매니페스트가 없다: ${file.absolutePath}", file.isFile)
        DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }.newDocumentBuilder().parse(file).documentElement
    }

    private companion object {
        const val APP_MERGED_MANIFEST = "build/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml"
    }

    private fun Element.children(tag: String): List<Element> {
        val list = getElementsByTagName(tag)
        return (0 until list.length).map { list.item(it) as Element }
    }

    private fun Element.a(name: String): String? = getAttributeNS(ns, name).takeIf { hasAttributeNS(ns, name) }

    private val application get() = manifest.children("application").single()

    private fun component(tag: String, name: String): Element =
        application.children(tag).firstOrNull { it.a("name") == name } ?: throw AssertionError("$tag $name 이 병합 매니페스트에 없다")

    @Test
    fun permissionsAreExactlyTheAllowList() {
        val permissions = manifest.children("uses-permission").mapNotNull { it.a("name") }.toSet()
        assertEquals(
            "권한 허용 목록(E§9.8)과 다르다",
            setOf(
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.POST_NOTIFICATIONS",
                "android.permission.VIBRATE",
                "android.permission.WAKE_LOCK",
                "com.google.android.c2dm.permission.RECEIVE",
                "android.permission.RECEIVE_BOOT_COMPLETED",
                "com.yehsung.aingcheck.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
            ),
            permissions,
        )
        assertFalse("광고 ID 권한이 있다", permissions.any { it.endsWith(".AD_ID") })
        assertTrue(manifest.children("uses-permission-sdk-23").isEmpty())
    }

    @Test
    fun backupIsOffAndCleartextIsOff() {
        assertEquals("false", application.a("allowBackup"))
        // Android 12+ 기기 이전은 allowBackup 을 무시한다 — fullBackupContent=false 가 Auto Backup·기기 이전 둘 다 끈다.
        assertEquals("false", application.a("fullBackupContent"))
        assertEquals("false", application.a("usesCleartextTraffic"))
        // 네트워크 보안 설정이 평문을 다시 여는 길을 두지 않는다.
        assertEquals(null, application.a("networkSecurityConfig"))
        assertEquals("com.yehsung.aingcheck.android.app.AingApplication", application.a("name"))
    }

    @Test
    fun singleLauncherActivityIsSingleTaskWithDeepLinks() {
        val main = component("activity", "com.yehsung.aingcheck.android.shell.MainActivity")
        // E-U16: 딥링크 → 프로세스 죽음 → 런처 아이콘에서 인스턴스가 하나 더 쌓이지 않게.
        assertEquals("singleTask", main.a("launchMode"))
        assertEquals("true", main.a("exported"))
        val filters = main.children("intent-filter")
        val actions = filters.map { f -> f.children("action").mapNotNull { it.a("name") }.toSet() }
        assertTrue(actions.any { "android.intent.action.MAIN" in it })
        val view = filters.single { f -> f.children("action").any { it.a("name") == "android.intent.action.VIEW" } }
        assertEquals(listOf("aingcheck"), view.children("data").mapNotNull { it.a("scheme") })
        assertEquals(
            setOf("android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"),
            view.children("category").mapNotNull { it.a("name") }.toSet(),
        )
        // 런처 진입은 이 Activity 하나뿐이다.
        val launchers = application.children("activity").filter { act ->
            act.children("category").any { it.a("name") == "android.intent.category.LAUNCHER" }
        }.mapNotNull { it.a("name") }
        assertEquals(listOf("com.yehsung.aingcheck.android.shell.MainActivity"), launchers)
    }

    @Test
    fun firebaseNeverAutoInitializes() {
        val providers = application.children("provider").mapNotNull { it.a("name") }
        assertFalse("FirebaseInitProvider 가 남아 있다(자동 초기화)", "com.google.firebase.provider.FirebaseInitProvider" in providers)
        val autoInit = application.children("meta-data").firstOrNull { it.a("name") == "firebase_messaging_auto_init_enabled" }
        assertEquals("false", autoInit?.a("value"))
        val service = component("service", "com.yehsung.aingcheck.android.push.AingMessagingService")
        assertEquals("false", service.a("exported"))
        assertTrue(service.children("action").any { it.a("name") == "com.google.firebase.MESSAGING_EVENT" })
    }
}
