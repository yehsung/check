// 원본: Sources/check/WorkTimerStore.swift:1142-1148 @ a63fea2 (맥은 UUID 를 defaults 에 한 번 만들어 둔다)
//       · 설계 D§2-5(저장 없이 다시 계산되는 값) · G §5-1 #6(레지스트리를 못 읽으면 무작위 UUID — 써 놓고 다시 읽어 같을 때만,
//         아니면 토큰 업로드 0) · 기억 device-identity-must-not-be-invented
//
// 왜 다시 계산하나: MSIX 는 제거 때 앱 데이터를 지운다. 무작위 ID 를 파일에 두면 재설치마다 새 기기가 되고, 같은 로컬
// 토큰 파일이 같은 달에 두 기기 행으로 올라가 순위표가 두 배가 된다. MSI 판과 Store 판을 오가도 같은 값이어야 한다.
// 한계: Sysprep 없이 복제한 VM 은 MachineGuid·SID 가 같다(드묾, D§2-5).
package com.yehsung.aingcheck.desktop.platform.windows.identity

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.UUID

/** 기기 신원의 재료. Windows 구현은 레지스트리·프로세스 토큰을 읽고, 시험은 가짜 값을 준다. 못 읽으면 null. */
interface MachineIdentitySource {
    fun machineGuid(): String?
    fun userSid(): String?
}

class WindowsInstallationIdentity(
    private val source: MachineIdentitySource,
    /** 레지스트리를 못 읽을 때만 쓰는 무작위 ID 파일(%LOCALAPPDATA%\aing-check\installation-id). */
    private val fallbackFile: Path,
    private val randomUuid: () -> UUID = UUID::randomUUID,
) : InstallationIdentity {
    enum class Origin { MACHINE_DERIVED, FALLBACK_FILE, UNAVAILABLE }

    data class Resolved(val installationId: String?, val origin: Origin)

    @Volatile private var cached: Resolved? = null

    override fun installationId(): String? = resolve().installationId

    /** 한 번 정해지면 이 프로세스 동안 그대로다(중간에 값이 바뀌면 같은 실행 안에서 두 기기가 된다). 실패는 캐시하지 않는다. */
    fun resolve(): Resolved {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val r = compute()
            if (r.installationId != null) cached = r
            return r
        }
    }

    private fun compute(): Resolved {
        val guid = runCatching { source.machineGuid() }.getOrNull()
        val sid = runCatching { source.userSid() }.getOrNull()
        if (guid != null && sid != null) {
            WindowsDeviceIdentity.installationId(guid, sid)?.let { return Resolved(it, Origin.MACHINE_DERIVED) }
        }
        return fallback()
    }

    /** 이미 확인된 파일이 있으면 그것, 없으면 새로 써 놓고 다시 읽어 같을 때만. 어느 단계든 어긋나면 null(닫힘). */
    private fun fallback(): Resolved {
        readValid()?.let { return Resolved(it, Origin.FALLBACK_FILE) }
        val fresh = randomUuid().toString().lowercase()
        return try {
            Files.createDirectories(fallbackFile.toAbsolutePath().parent)
            val tmp = Files.createTempFile(fallbackFile.toAbsolutePath().parent, ".id-", ".tmp")
            try {
                Files.writeString(tmp, fresh + "\n")
                try {
                    Files.move(tmp, fallbackFile, StandardCopyOption.ATOMIC_MOVE)
                } catch (_: AtomicMoveNotSupportedException) {
                    Files.move(tmp, fallbackFile)
                }
            } finally {
                runCatching { Files.deleteIfExists(tmp) }
            }
            val back = readValid()
            if (back == fresh) Resolved(fresh, Origin.FALLBACK_FILE) else Resolved(null, Origin.UNAVAILABLE)
        } catch (_: Exception) {
            // 다른 실행이 먼저 썼을 수 있다(FileAlreadyExists) — 그 값이 확인되면 그것을 쓴다.
            readValid()?.let { Resolved(it, Origin.FALLBACK_FILE) } ?: Resolved(null, Origin.UNAVAILABLE)
        }
    }

    private fun readValid(): String? {
        val text = runCatching { Files.readString(fallbackFile) }.getOrNull()?.trim() ?: return null
        val parsed = runCatching { UUID.fromString(text) }.getOrNull() ?: return null
        val canonical = parsed.toString()
        return if (canonical == text.lowercase()) canonical else null
    }
}
