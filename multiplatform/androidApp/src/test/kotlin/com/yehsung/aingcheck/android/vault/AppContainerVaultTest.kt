// E§5.2: 운영 금고는 noBackupFilesDir 아래에만 쓴다(백업·기기 이전에서 빠진다). 설치 UUID 시험(appIdentityLivesInNoBackupFilesDir)과
// 같은 꼴로 **그릇(AppContainer)이 고른 자리**를 잰다 — 시험이 디렉터리를 직접 정하지 않는다.
// Robolectric 에는 AndroidKeyStore 가 없어 봉투만 소프트웨어로 바꾼다(그릇의 vaultCipher 자리). 자리·파일 이름·임시 파일은 운영과 같다.
package com.yehsung.aingcheck.android.vault

import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.app.AppContainer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AppContainerVaultTest {
    private fun snapshot(root: File): Map<String, Pair<Long, Long>> =
        root.walkTopDown().filter { it.isFile }.associate { it.canonicalPath to (it.length() to it.lastModified()) }

    @Test
    fun containerVaultWritesOnlyUnderNoBackupFilesDir() {
        val app = ApplicationProvider.getApplicationContext<AingApplication>()
        val container = AppContainer(app) { SoftwareVaultCipher(seed = 11) }
        val dataDir = app.filesDir.parentFile!!
        val noBackup = app.noBackupFilesDir.canonicalPath
        assertTrue("시험 전제: noBackupFilesDir 가 앱 데이터 디렉터리 안이다", noBackup.startsWith(dataDir.canonicalPath))

        val before = snapshot(dataDir)
        container.tokenVault.write("refresh-marker-value", "refresh")
        // 기준선: 실제로 썼다(봉투가 실패해 아무 파일도 안 생긴 '빈 초록'이 아니다).
        assertEquals("refresh-marker-value", container.tokenVault.read("refresh"))
        val after = snapshot(dataDir)
        val touched = after.filter { (path, meta) -> before[path] != meta }.keys + (before.keys - after.keys)

        assertTrue("금고 쓰기가 데이터 디렉터리에 아무 흔적도 남기지 않았다", touched.isNotEmpty())
        val outside = touched.filterNot { it.startsWith(noBackup + File.separator) }
        assertEquals("금고가 백업되는 자리(filesDir·shared_prefs 등)에 썼다", emptyList<String>(), outside)
        // filesDir·shared_prefs 이름으로도 한 번 더(위 판정의 거울이 아니라 자리 이름으로).
        val backedUp = listOf(app.filesDir.canonicalPath, File(dataDir, "shared_prefs").canonicalPath)
        assertEquals(emptyList<String>(), touched.filter { p -> backedUp.any { p.startsWith(it + File.separator) } })
    }
}
