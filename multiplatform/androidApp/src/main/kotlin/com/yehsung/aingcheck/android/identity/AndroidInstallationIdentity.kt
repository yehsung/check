// 원본: Sources/CheckMobileKit/Session/MobileDeviceService.swift(설치 UUID) @ a63fea2 · E§5.2 · C§3.4 · K3 InstallationIdentity
// 설치(기기) 식별자 = 소문자 UUID 하나. 서버 client_devices 는 (user_id, installation_id) 유일이라, 새 폰에 같은 값이 복원되면
// 두 기기가 한 행을 덮어쓴다(FCM 토큰이 번갈아 바뀐다). 그래서:
// - 자리는 noBackupFilesDir(Auto Backup·기기 이전 모두 플랫폼이 건너뛴다) — 매니페스트의 allowBackup=false·fullBackupContent=false 와 겹으로.
// - **저장 확인 뒤에만** 돌려준다(기억 device-identity-must-not-be-invented): 써 놓고 다시 읽어 같을 때만 값, 아니면 null.
//   호출자는 null 이면 기기 단위 쓰기(등록·토큰 업로드)를 하지 않는다.
// - 재설치하면 새 값이 생긴다(iOS 키체인과 다름) — 서버가 사용자당 10대로 자른다.
package com.yehsung.aingcheck.android.identity

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class AndroidInstallationIdentity(
    /** 운영은 Context.noBackupFilesDir. */
    private val dir: File,
    private val newUuid: () -> UUID = UUID::randomUUID,
) : InstallationIdentity {
    private var confirmed: String? = null

    val file: File get() = File(dir, FILE_NAME)

    @Synchronized
    override fun installationId(): String? {
        confirmed?.let { return it }
        readValid()?.let { confirmed = it; return it }
        val fresh = newUuid().toString().lowercase()
        val temp = File(dir, "$FILE_NAME.tmp")
        val wrote = runCatching {
            if (!dir.isDirectory && !dir.mkdirs()) error("디렉터리를 못 만든다")
            FileOutputStream(temp).use { out ->
                out.write(fresh.toByteArray(Charsets.US_ASCII))
                out.fd.sync()
            }
            check(temp.renameTo(file)) { "이름 바꾸기 실패" }
        }.isSuccess
        if (!wrote) {
            temp.delete()
            return null
        }
        // 다시 읽어 같을 때만 확정한다.
        return readValid()?.takeIf { it == fresh }?.also { confirmed = it }
    }

    private fun readValid(): String? = runCatching {
        if (!file.isFile) return null
        file.readText(Charsets.US_ASCII).trim().takeIf { UUID_LOWER.matches(it) }
    }.getOrNull()

    companion object {
        const val FILE_NAME = "installation-id"
        val UUID_LOWER = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    }
}
