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

/**
 * 폴백 ID 의 저장 이음매. 앱은 [FileFallbackIdStore], 시험은 "쓰기는 성공했는데 다시 읽으니 다르다"·"다시 읽기 실패"를
 * 주입한다 — 디스크로는 그 경우를 싸게 만들 수 없어서, 이 이음매가 없으면 '다시 읽어 같을 때만' 규칙을 잴 수 없다.
 */
interface FallbackIdStore {
    /** 저장된 글. 없으면 null, 읽기 실패는 예외. */
    fun read(): String?

    /** 통째로 바꿔 쓴다. 실패는 예외. */
    fun write(text: String)
}

/** %LOCALAPPDATA%\aing-check\installation-id — 같은 폴더의 임시 파일에 쓰고 원자 이동한다. */
class FileFallbackIdStore(private val file: Path) : FallbackIdStore {
    override fun read(): String? = if (Files.exists(file)) Files.readString(file) else null

    override fun write(text: String) {
        val dir = file.toAbsolutePath().parent
        Files.createDirectories(dir)
        val tmp = Files.createTempFile(dir, ".id-", ".tmp")
        try {
            Files.writeString(tmp, text)
            try {
                Files.move(tmp, file, StandardCopyOption.ATOMIC_MOVE)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(tmp, file)
            }
        } finally {
            runCatching { Files.deleteIfExists(tmp) }
        }
    }
}

class WindowsInstallationIdentity(
    private val source: MachineIdentitySource,
    /** 레지스트리를 못 읽을 때만 쓰는 무작위 ID 저장소. */
    private val store: FallbackIdStore,
    private val randomUuid: () -> UUID = UUID::randomUUID,
) : InstallationIdentity {
    /** 앱 조립: [fallbackFile] = %LOCALAPPDATA%\aing-check\installation-id(MSIX 안이면 리디렉션 자리, WindowsAppPaths). */
    constructor(source: MachineIdentitySource, fallbackFile: Path, randomUuid: () -> UUID = UUID::randomUUID) :
        this(source, FileFallbackIdStore(fallbackFile), randomUuid)

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

    /**
     * 이미 확인된 파일이 있으면 그것, 없으면 새로 써 놓고 **다시 읽어 같을 때만**. 어느 단계든 어긋나면 null(닫힘) —
     * "썼다"는 사실만 믿고 쓰면, 저장이 조용히 다른 자리로 가거나 사라진 기기가 실행마다 새 기기가 된다
     * (기억 device-identity-must-not-be-invented: 순위표 두 배).
     */
    private fun fallback(): Resolved {
        readValid()?.let { return Resolved(it, Origin.FALLBACK_FILE) }
        val fresh = randomUuid().toString().lowercase()
        val wrote = runCatching { store.write(fresh + "\n") }.isSuccess
        if (!wrote) {
            // 다른 실행이 먼저 썼을 수 있다(FileAlreadyExists) — 그 값이 확인되면 그것을 쓴다.
            return readValid()?.let { Resolved(it, Origin.FALLBACK_FILE) } ?: Resolved(null, Origin.UNAVAILABLE)
        }
        val back = readValid()
        return if (back == fresh) Resolved(fresh, Origin.FALLBACK_FILE) else Resolved(null, Origin.UNAVAILABLE)
    }

    private fun readValid(): String? {
        val text = runCatching { store.read() }.getOrNull()?.trim() ?: return null
        val parsed = runCatching { UUID.fromString(text) }.getOrNull() ?: return null
        val canonical = parsed.toString()
        return if (canonical == text.lowercase()) canonical else null
    }
}
