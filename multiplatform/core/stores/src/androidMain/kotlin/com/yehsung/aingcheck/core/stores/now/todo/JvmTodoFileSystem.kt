// 원본: Sources/CheckCore/CheckTodoModel.swift:465-487(TodoFileStore.load·save — FileManager · Data.write(.atomic)) ·
//       Sources/CheckMobileKit/Now/NowTodoSupport.swift:98-120(NowTodoFileAccess — 조정 구간) @ 1b8260d
// Android·데스크톱 둘 다 JVM 이라 같은 몸통이다(소스셋마다 actual 이 하나씩 있어야 한다).
package com.yehsung.aingcheck.core.stores.now.todo

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * 진짜 파일 시스템(Swift `FileManager` + `Data.write(options: .atomic)`). 쓰기는 같은 폴더의 임시 파일에 쓰고 `fsync` 한 뒤
 * 원자적 이름 바꾸기로 덮는다 — 쓰는 도중 앱이 죽어도 반쯤 쓰인 JSON 이 남지 않는다(남으면 다음 실행이 손상으로 보고 백업으로 치운다).
 */
class JvmTodoFileSystem : TodoFileSystem {
    override fun read(path: String): ByteArray? {
        val file = File(path)
        if (!file.exists()) return null
        return file.readBytes()
    }

    override fun writeAtomically(path: String, bytes: ByteArray) {
        val target = File(path)
        val directory = target.absoluteFile.parentFile ?: throw IOException("폴더가 없는 경로: $path")
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) throw IOException("폴더를 만들지 못했다: $directory")
        val temporary = File.createTempFile(".${target.name}.", ".tmp", directory)
        try {
            FileOutputStream(temporary).use { out ->
                out.write(bytes)
                out.fd.sync()
            }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    override fun move(from: String, to: String) {
        try {
            Files.move(File(from).toPath(), File(to).toPath(), StandardCopyOption.REPLACE_EXISTING)
        } catch (error: IOException) {
            // 옮기지 못하면 원본이 그대로 남는다 — 다음 쓰기가 덮기 전까지는 읽을 수 있다(Swift `try? moveItem`).
        }
    }
}
