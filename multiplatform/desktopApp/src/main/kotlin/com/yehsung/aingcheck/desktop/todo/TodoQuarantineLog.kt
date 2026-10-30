// 원본: 없음(새 코드) — int-w3 asm unresolved[4]("할 일 격리 보고는 System.err 한 줄 — 로그 파일 통로 없음") · int-w4a polish ⑤.
// 맥은 진단을 사용자 로그 폴더의 앱 이름 파일에 덧붙인다(CheckUpdateCheck.swift:1027 `~/Library/Logs/aing-check-update.log` ·
// AppStoreEditionRetirement.swift:435 `aing-check-retire.log` — 이 기기에만 남고 전송 없음, 사용자가 붙여 넣을 수 있게).
// Windows 배포본은 콘솔이 없어 System.err 는 아무 데도 남지 않는다 — 같은 꼴로 앱 로그 폴더(AppPaths.logDir)에 한 줄씩 덧붙인다.
// 맥 두 로그는 상한이 없지만(드문 사건) 여기는 크기 상한 + 한 세대 회전(<이름>.1)을 둔다 — 손상 파일이 되풀이되는 기기에서 끝없이 자라지 않게.
package com.yehsung.aingcheck.desktop.todo

import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import kotlin.time.Instant

/**
 * 덧붙이기 로그 파일 하나. 쓰기 전 [file] 이 [maxBytes] 이상이면 `<이름>.1` 로 옮기고(앞 세대는 덮는다) 새 파일에 쓴다.
 * 실패는 삼킨다(진단 로그가 할 일 저장을 막지 않는다) — [append] 가 false 를 돌려준다.
 */
class RotatingLogFile(val file: Path, private val maxBytes: Long = DEFAULT_MAX_BYTES) {
    @Synchronized
    fun append(line: String): Boolean = runCatching {
        file.parent?.let { Files.createDirectories(it) }
        if (Files.exists(file) && Files.size(file) >= maxBytes) {
            Files.move(file, rotated, StandardCopyOption.REPLACE_EXISTING)
        }
        Files.write(
            file,
            (line.replace('\n', ' ') + "\n").toByteArray(StandardCharsets.UTF_8),
            StandardOpenOption.CREATE, StandardOpenOption.APPEND, StandardOpenOption.WRITE,
        )
    }.isSuccess

    /** 회전된 앞 세대. */
    val rotated: Path get() = file.resolveSibling(file.fileName.toString() + ".1")

    companion object {
        /** 256KB — 격리 한 줄이 ~200바이트라 천 건 넘게 담는다. */
        const val DEFAULT_MAX_BYTES: Long = 256L * 1024
    }
}

/** 할 일 손상 파일 격리 보고 → 앱 로그 폴더의 `aing-check-todo.log` 한 줄(DesktopTodoFileSystem.onQuarantine). */
object TodoQuarantineLog {
    const val FILE_NAME = "aing-check-todo.log"

    /**
     * 로그 폴더: [AppPaths.logDir](Windows `%LOCALAPPDATA%\aing-check\logs`). 비었거나 절대 경로가 아니면(작업 폴더에 따라 자리가 바뀐다)
     * `dataDir/logs`.
     */
    fun dir(paths: AppPaths): Path {
        val log = paths.logDir.takeIf { it.isNotBlank() }?.let { runCatching { Path.of(it) }.getOrNull() }
        return if (log != null && log.isAbsolute) log else Path.of(paths.dataDir, "logs")
    }

    /** 한 줄 꼴(시각 · 원본 · 백업 · 크기 · 옮김/베낌 · 보존). 사용자 문장은 싣지 않는다(경로·숫자만). */
    fun line(q: TodoQuarantine, at: Instant): String =
        "$at todo quarantine original=${q.originalPath} backup=${q.backupPath} bytes=${q.bytes} moved=${q.moved} preserved=${q.preserved}"

    /** DesktopTodoFileSystem.onQuarantine 에 넣을 받는 쪽. */
    fun sink(paths: AppPaths, now: () -> Instant, maxBytes: Long = RotatingLogFile.DEFAULT_MAX_BYTES): (TodoQuarantine) -> Unit {
        val file = RotatingLogFile(dir(paths).resolve(FILE_NAME), maxBytes)
        return { q -> file.append(line(q, now())) }
    }
}
