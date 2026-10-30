// 원본: 없음(시험 위생 — int-w3 반박 nice_to_have[2] · int-w4a polish ⑥). 실제 그래프(AppGraph.assemble)를 짓는 시험은 dataDir 아래에
// 할 일 목록(todos.<계정>.json)·격리 백업·앱 로그를 쓴다. `deleteOnExit()` 는 **빈 폴더만** 지워 그 파일들이 임시 폴더에 쌓였다 —
// 시험이 끝나면(@AfterTest) 통째로 지운다.
package com.yehsung.aingcheck.desktop.wiring

import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.ConcurrentLinkedQueue

/** 한 시험 몫의 임시 dataDir 묶음. [new] 로 만들고 [close] 가 안의 파일째 지운다(@AfterTest 에서 부른다). */
internal class TempDataDirs : AutoCloseable {
    private val dirs = ConcurrentLinkedQueue<Path>()

    fun new(prefix: String): Path = Files.createTempDirectory(prefix).also { dirs.add(it) }

    /** 만든 폴더(시험 · 진단). */
    val created: List<Path> get() = dirs.toList()

    override fun close() {
        while (true) {
            val d = dirs.poll() ?: break
            d.toFile().deleteRecursively()
        }
    }
}
