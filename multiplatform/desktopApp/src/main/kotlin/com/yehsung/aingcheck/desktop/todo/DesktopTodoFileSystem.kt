// 원본: Sources/CheckCore/CheckTodoModel.swift:446-503(TodoFileStore — defaultURL · load 는 던진다 · save 는 Data.write(.atomic)) ·
//       :505-560(TodoListStore.reload — 손상 파일을 `.corrupt-<KST 시각>` 으로 옮기고 빈 목록) @ 1b8260d
// 데스크톱(Windows) 할 일 파일 자리. 엔진(TodoListStore·TodoFileStore — core/stores …/now/todo)은 그대로 쓰고, 여기는 java.nio 로 바이트만 나른다.
package com.yehsung.aingcheck.desktop.todo

import com.yehsung.aingcheck.core.stores.now.todo.TodoFileStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

/**
 * 손상 파일 격리 한 건(손실 범위 보고). 엔진은 손상 파일을 만나면 [TodoFileSystem.move] 로 백업 자리에 옮기고 **빈 목록**으로 출발한다
 * (TodoListStore.reload). 그 순간 화면 목록에서 빠지는 것은 원본 파일 전체([bytes] 바이트)다 — [preserved] 면 [backupPath] 에 바이트 그대로
 * 남아 있어 사용자 문장은 잃지 않았다. [preserved] 가 거짓이면 옮기지도 베끼지도 못했다는 뜻이고, 다음 저장이 원본을 덮으면 그 바이트는 사라진다.
 */
data class TodoQuarantine(
    val originalPath: String,
    val backupPath: String,
    /** 격리한 원본 크기(바이트). 읽지 못했으면 -1. */
    val bytes: Long,
    /** true = 옮김(move), false = 옮기지 못해 베낌(copy) 또는 실패. */
    val moved: Boolean,
    /** 백업 자리에 원본 바이트가 남았는가(옮김 또는 베낌 성공). */
    val preserved: Boolean,
)

/**
 * 진짜 파일 시스템(java.nio — 맥 `FileManager` + `Data.write(options: .atomic)`).
 * - 쓰기: 같은 폴더의 임시 파일(`.<이름>.<난수>.tmp`)에 쓰고 `force` 한 뒤 원자 이동으로 덮는다. 쓰다 죽어도 반쯤 쓰인 JSON 이 남지 않는다.
 *   원자 이동을 못 하는 볼륨이면 일반 덮어쓰기 이동으로 한 번 더 한다(그래도 임시 파일 → 이동이라 원본이 반쯤 잘리지는 않는다).
 * - 손상 백업([move]): 옮기지 못하면(Windows — 다른 프로세스가 파일을 쥐고 있을 때) **베껴 둔다**. 맥은 `try? moveItem` 로 실패를 삼키지만
 *   그러면 다음 저장이 원본을 덮어 사용자 문장이 사라진다 — 베끼기는 그 창을 닫는다. 결과는 [quarantines]·[onQuarantine] 로 보고한다.
 */
class DesktopTodoFileSystem(
    /** 격리 보고(로그·진단). 엔진이 부르는 줄기(UI)에서 불린다. */
    private val onQuarantine: (TodoQuarantine) -> Unit = {},
    /** 옮기기(시험이 실패를 꽂는 문). */
    private val mover: (Path, Path) -> Unit = { from, to -> Files.move(from, to, StandardCopyOption.REPLACE_EXISTING) },
) : TodoFileSystem {
    private val reports = mutableListOf<TodoQuarantine>()

    /** 이 실행에서 격리한 파일들(오래된 것부터). */
    val quarantines: List<TodoQuarantine> get() = reports.toList()

    override fun read(path: String): ByteArray? {
        val file = Path.of(path)
        return try {
            Files.readAllBytes(file)
        } catch (missing: NoSuchFileException) {
            null
        }
    }

    override fun writeAtomically(path: String, bytes: ByteArray) {
        val target = Path.of(path).toAbsolutePath()
        val directory = target.parent ?: throw IOException("폴더가 없는 경로: $path")
        Files.createDirectories(directory)
        val temporary = Files.createTempFile(directory, ".${target.fileName}.", ".tmp")
        try {
            FileChannel.open(temporary, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING).use { channel ->
                val buffer = ByteBuffer.wrap(bytes)
                while (buffer.hasRemaining()) channel.write(buffer)
                channel.force(true)
            }
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (unsupported: AtomicMoveNotSupportedException) {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING)
            }
        } finally {
            Files.deleteIfExists(temporary)
        }
    }

    override fun move(from: String, to: String) {
        val source = Path.of(from)
        val backup = Path.of(to)
        val bytes = try {
            Files.size(source)
        } catch (error: IOException) {
            -1L
        }
        var moved = false
        var preserved = false
        try {
            mover(source, backup)
            moved = true
            preserved = true
        } catch (error: IOException) {
            preserved = try {
                Files.copy(source, backup, StandardCopyOption.REPLACE_EXISTING)
                true
            } catch (copyError: IOException) {
                false
            }
        }
        val report = TodoQuarantine(from, to, bytes, moved, preserved)
        reports += report
        onQuarantine(report)
    }

    companion object {
        /**
         * 계정별 할 일 파일(맥 `TodoFileStore.defaultURL(userID:)` = `Application Support/aing-check/todos.<계정>.json` 과 같은 뜻 —
         * 데스크톱은 [dataDir] = `%LOCALAPPDATA%\aing-check`). 파일 이름 규칙(안전 글자만 · 로그아웃 = `todos.local.json`)은
         * [TodoFileStore.path] 한 곳에서만 만든다 — 여기는 그 이름을 폴더에 붙이기만 한다(규칙을 두 번 적지 않는다).
         */
        fun path(dataDir: Path, userID: String?): String {
            val name = TodoFileStore.path("", userID).substringAfterLast('/')
            return dataDir.resolve(name).toAbsolutePath().toString()
        }
    }
}
