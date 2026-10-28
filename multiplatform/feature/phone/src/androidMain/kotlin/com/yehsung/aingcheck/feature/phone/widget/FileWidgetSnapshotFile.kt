// 원본: Sources/CheckMobileShared/WidgetSnapshot.swift:348-362(WidgetSnapshotCodec.read · write(.atomic) · remove) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * 진짜 파일 하나(앱 전용 폴더 `filesDir/widget-snapshot.json` — 조립이 경로를 넘긴다). 쓰기는 같은 폴더의 임시 파일에 쓰고 `fsync` 한 뒤
 * 원자적 이름 바꾸기로 덮는다(Swift `Data.write(options: .atomic)`) — 위젯이 반쯤 쓰인 JSON 을 읽지 않는다.
 */
class FileWidgetSnapshotFile(private val target: File) : WidgetSnapshotFile {
    override fun read(): ByteArray? = try {
        if (target.isFile) target.readBytes() else null
    } catch (error: IOException) {
        null
    }

    override fun writeAtomically(bytes: ByteArray) {
        val directory = target.absoluteFile.parentFile ?: throw IOException("폴더가 없는 경로: $target")
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

    override fun remove() {
        target.delete()
    }
}
