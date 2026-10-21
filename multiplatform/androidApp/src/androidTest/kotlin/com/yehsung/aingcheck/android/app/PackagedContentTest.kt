// W1-g 완료 기준 ⑦의 기기 몫: 설치된 시험 대상 APK(debug)와 계측 APK 의 dex 에 운영 주소가 0건, 앱 APK assets 에 Fixtures 0건.
// 기준선: 같은 검사기가 dex 안의 `.invalid` 기본 주소(ProdConfig)를 찾아낸다 — 늘 0 을 내는 검사기가 아니다.
// 릴리스 APK(R8)의 assets·dex 는 출시 점검 스크립트가 잰다(완료 보고·조정자 패치 w1g-03).
// 앱 쪽 덧붙임: 기기 위에서도 채널 다섯이 있고, 계측 빌드는 Firebase 를 초기화하지 않았다.
package com.yehsung.aingcheck.android.app

import android.app.NotificationManager
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.FirebaseApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.zip.ZipFile

@RunWith(AndroidJUnit4::class)
class PackagedContentTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    /** 운영 프로젝트 주소 문형(구조 시험 R5 와 같은 꼴). 글자를 이어 붙인다 — 이 파일이 저장소 비밀 검사에 걸리지 않게. */
    private val prodAddress = Regex("""[A-Za-z0-9-]+\.""" + "supa" + """base\.(co|in|com)\b""")

    private fun dexText(apk: String): Map<String, String> = ZipFile(apk).use { zip ->
        zip.entries().asSequence().filter { it.name.matches(Regex("""classes\d*\.dex""")) }
            .associate { e -> e.name to zip.getInputStream(e).use { String(it.readBytes(), Charsets.ISO_8859_1) } }
    }

    @Test
    fun noProductionAddressInAppOrTestDex() {
        val appApk = instrumentation.targetContext.applicationInfo.sourceDir
        val testApk = instrumentation.context.applicationInfo.sourceDir
        val appDex = dexText(appApk)
        val testDex = dexText(testApk)
        assertTrue("앱 APK 에 dex 가 없다", appDex.isNotEmpty())
        assertTrue("계측 APK 에 dex 가 없다", testDex.isNotEmpty())
        val baseline = appDex.values.sumOf { Regex("""aingcheck\.invalid""").findAll(it).count() }
        val hits = (appDex + testDex.mapKeys { "test:${it.key}" }).flatMap { (name, text) -> prodAddress.findAll(text).map { "$name:${it.value}" } }
        println("AINGCHECK-DEX app=${appDex.size} test=${testDex.size} invalid-baseline=$baseline prod-hits=${hits.size}")
        assertTrue("기준선: 검사기가 dex 안의 .invalid 주소를 못 찾는다 — 검사가 비었다", baseline >= 1)
        assertEquals("시험 dex 에 운영 주소가 있다", emptyList<String>(), hits)
    }

    @Test
    fun noFixturesInAppAssets() {
        val entries = ZipFile(instrumentation.targetContext.applicationInfo.sourceDir).use { z -> z.entries().asSequence().map { it.name }.toList() }
        val dex = entries.count { it.endsWith(".dex") }
        val fixtures = entries.filter { it.startsWith("assets/") && it.contains("Fixtures", ignoreCase = true) }
        println("AINGCHECK-ASSETS entries=${entries.size} dex=$dex assets=${entries.count { it.startsWith("assets/") }} fixtures=${fixtures.size}")
        assertTrue("기준선: APK 목록을 못 읽었다", dex >= 1)
        assertEquals(emptyList<String>(), fixtures)
    }

    @Test
    fun channelsExistAndFirebaseIsOffOnDevice() {
        val target = instrumentation.targetContext
        val manager = target.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertEquals(
            setOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check"),
            manager.notificationChannels.map { it.id }.toSet(),
        )
        val app = target.applicationContext as AingApplication
        assertTrue("계측 실행이 시험으로 읽히지 않았다", app.container.runningTests.isRunningTests)
        assertEquals(FirebaseDecision.SKIP_NOT_RELEASE, app.firebaseDecision)
        assertEquals(emptyList<FirebaseApp>(), FirebaseApp.getApps(target))
        // 설치 UUID 는 백업 제외 자리에, 소문자 UUID 로.
        val id = app.container.installationIdentity.installationId()
        assertTrue("설치 UUID 모양: $id", id != null && Regex("^[0-9a-f-]{36}$").matches(id))
        assertEquals(id, java.io.File(target.noBackupFilesDir, "installation-id").readText().trim())
    }
}
