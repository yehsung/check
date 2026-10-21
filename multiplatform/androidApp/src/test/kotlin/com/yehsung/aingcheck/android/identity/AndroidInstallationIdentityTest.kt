// K3 InstallationIdentity(Android): 저장 확인 뒤에만 값 · 소문자 UUID · 같은 설치는 같은 값 · 다른 설치는 다른 값 · noBackupFilesDir.
package com.yehsung.aingcheck.android.identity

import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.nio.file.Files
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AndroidInstallationIdentityTest {
    private fun tempDir(): File = Files.createTempDirectory("ident").toFile()

    @Test
    fun appIdentityLivesInNoBackupFilesDir() {
        val app = ApplicationProvider.getApplicationContext<AingApplication>()
        val id = app.container.installationIdentity.installationId()
        assertNotNull(id)
        val file = File(app.noBackupFilesDir, AndroidInstallationIdentity.FILE_NAME)
        assertEquals("설치 UUID 가 백업 제외 자리(noBackupFilesDir)에 없다", id, file.readText().trim())
        // 백업되는 자리(filesDir·shared_prefs)에는 이 값이 없다.
        val leaked = app.filesDir.parentFile!!.walkTopDown()
            .filter { it.isFile && !it.canonicalPath.startsWith(app.noBackupFilesDir.canonicalPath) }
            .filter { runCatching { it.readText().contains(id!!) }.getOrDefault(false) }
            .toList()
        assertEquals("설치 UUID 가 백업되는 자리에도 있다: $leaked", emptyList<File>(), leaked)
    }

    @Test
    fun sameInstallSameValueOtherInstallOtherValue() {
        val dir = tempDir()
        val first = AndroidInstallationIdentity(dir).installationId()!!
        assertTrue(AndroidInstallationIdentity.UUID_LOWER.matches(first))
        assertEquals("같은 설치(다음 실행)는 같은 값", first, AndroidInstallationIdentity(dir).installationId())
        assertNotEquals("다른 설치(재설치)는 다른 값", first, AndroidInstallationIdentity(tempDir()).installationId())
    }

    @Test
    fun uppercaseSourceIsStoredLowercase() {
        val fixed = UUID.fromString("ABCDEF00-0000-4000-8000-0000000000AA")
        assertEquals("abcdef00-0000-4000-8000-0000000000aa", AndroidInstallationIdentity(tempDir()) { fixed }.installationId())
    }

    @Test
    fun unwritableStorageInventsNothing() {
        val dir = tempDir()
        check(dir.setWritable(false))
        try {
            assertNull("저장 확인 없이 지어낸 값을 돌려줬다", AndroidInstallationIdentity(dir).installationId())
        } finally {
            dir.setWritable(true)
        }
        // 기준선: 같은 자리가 쓰이게 되면 값이 생긴다.
        assertNotNull(AndroidInstallationIdentity(dir).installationId())
    }

    @Test
    fun corruptedFileIsReplacedNotReturned() {
        val dir = tempDir()
        File(dir, AndroidInstallationIdentity.FILE_NAME).writeText("not-a-uuid")
        val id = AndroidInstallationIdentity(dir).installationId()!!
        assertTrue(AndroidInstallationIdentity.UUID_LOWER.matches(id))
    }
}
