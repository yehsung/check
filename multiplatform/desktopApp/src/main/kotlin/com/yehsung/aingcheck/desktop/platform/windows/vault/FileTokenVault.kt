// 원본: Sources/CheckCore/TokenVault.swift @ a63fea2 (계약: 실패를 삼키되 write 가 실패한 키는 read 가 반드시 nil — '없다 > 낡았다')
//       · 설계 D§7(DPAPI 파일 금고: %LOCALAPPDATA%\aing-check\vault\<sha256(키)>.bin, 엔트로피 "aing-check.v1|"+키,
//         쓰기는 임시 파일 → 원자 이동, 어느 단계든 실패하면 대상 파일을 지운다, 복호화 실패는 nil + 손상 파일 삭제)
//
// 암호화는 [DataProtector] 뒤에 둔다: 앱은 [DpapiProtector](Windows 사용자 범위 DPAPI), 맥 JVM 시험은 가짜 보호기로
// 같은 파일 규약을 잰다. 계약 시험은 testkit TokenVaultContract — 맥(가짜 보호기)·Windows 러너(진짜 DPAPI) 둘 다에서 돈다.
//
// 실패의 사다리(낡은 값이 살아남지 않게):
//   ① 쓰기 실패 → 대상 파일 삭제 → ② 삭제도 실패(폴더 쓰기 금지·잠금) → 대상 파일을 0바이트로 자른다(복호화 실패 = nil,
//   앱을 다시 켜도 낡은 값이 돌아오지 않는다) → ③ 그래도 안 되면 이 프로세스가 사는 동안 그 키를 '독(poisoned)'으로 둬 read 가 nil.
//   다음에 쓰기·삭제가 성공하면 독을 푼다. ③ 까지 간 파일은 다음 실행에서 다시 읽힐 수 있다 — 쓸 수도 지울 수도 자를 수도
//   없는 파일이라 이 프로세스가 더 할 수 있는 일이 없다(남은 위험으로 보고했다).
package com.yehsung.aingcheck.desktop.platform.windows.vault

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** 바이트를 사용자 범위로 봉인·해제한다. 실패는 예외로 알린다(금고가 삼킨다). */
interface DataProtector {
    fun protect(plain: ByteArray, entropy: ByteArray): ByteArray
    fun unprotect(sealed: ByteArray, entropy: ByteArray): ByteArray
}

class FileTokenVault(
    private val directory: Path,
    private val protector: DataProtector,
) : TokenVault {
    private val poisoned: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val lock = Any()

    override fun read(key: String): String? = synchronized(lock) {
        if (key in poisoned) return null
        val file = fileFor(key)
        val sealed = try {
            if (!Files.isRegularFile(file)) return null
            Files.readAllBytes(file)
        } catch (_: Exception) {
            return null
        }
        val plain = try {
            protector.unprotect(sealed, entropy(key))
        } catch (_: Exception) {
            // 손상·다른 사용자·다른 기기의 파일: 지우고 '없다'(재로그인)로 간다.
            runCatching { Files.deleteIfExists(file) }
            return null
        }
        decodeUtf8(plain)
    }

    override fun write(value: String, key: String) {
        synchronized(lock) { writeLocked(value, key) }
    }

    private fun writeLocked(value: String, key: String) {
        val file = fileFor(key)
        var tmp: Path? = null
        try {
            val sealed = protector.protect(value.toByteArray(Charsets.UTF_8), entropy(key))
            Files.createDirectories(directory)
            tmp = Files.createTempFile(directory, ".w-", ".tmp")
            Files.newOutputStream(tmp, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.SYNC).use {
                it.write(sealed)
            }
            try {
                Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING)
            }
            tmp = null
            poisoned.remove(key)
        } catch (_: Exception) {
            tmp?.let { t -> runCatching { Files.deleteIfExists(t) } }
            discardStale(key, file)
        }
    }

    override fun delete(key: String) {
        synchronized(lock) {
            val file = fileFor(key)
            val gone = runCatching { Files.deleteIfExists(file) }.isSuccess && !Files.exists(file)
            if (gone) poisoned.remove(key) else discardStale(key, file)
        }
    }

    /** 낡은 값이 read 로 돌아오지 않게 한다(위 사다리 ①~③). */
    private fun discardStale(key: String, file: Path) {
        poisoned.add(key)
        val deleted = runCatching { Files.deleteIfExists(file) }.isSuccess && !Files.exists(file)
        if (deleted) return
        runCatching {
            Files.newOutputStream(file, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING).use { }
        }
    }

    /** 키 이름은 파일 이름에 드러내지 않는다(sha256 16진). */
    fun fileFor(key: String): Path = directory.resolve(sha256Hex(key) + ".bin")

    private fun entropy(key: String): ByteArray = (ENTROPY_PREFIX + key).toByteArray(Charsets.UTF_8)

    private fun decodeUtf8(bytes: ByteArray): String? = try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(java.nio.ByteBuffer.wrap(bytes))
            .toString()
    } catch (_: CharacterCodingException) {
        null
    }

    companion object {
        /** DPAPI 엔트로피 앞머리(D§7). 바꾸면 기존 금고를 못 연다 — 판을 올릴 때만. */
        const val ENTROPY_PREFIX = "aing-check.v1|"

        fun sha256Hex(text: String): String =
            MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
