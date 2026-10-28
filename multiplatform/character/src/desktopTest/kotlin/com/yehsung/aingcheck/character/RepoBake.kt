// 원본: 없음 (시험 보조 — 구운 자산 · 골든을 저장소 제자리에서 읽는다. 복사하지 않는다, A§4-2)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.parity.Golden
import com.yehsung.aingcheck.character.parity.GoldenSet
import java.io.File

/** 저장소 뿌리(`aingcheck.repoRoot`, Gradle 시험 작업이 넣는다) 기준. */
object RepoBake {
    val repoRoot: File = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다 — Gradle 시험 작업으로 돌린다" })
    val bakeRoot = File(repoRoot, "multiplatform/assets/aing-bake")
    val haloRoot = File(repoRoot, "Sources/check/Resources")

    /** 저장소 파일을 그대로 읽는 [BakeFiles]. [hide] 에 든 경로는 없는 것으로, [override] 는 바꿔 끼운 바이트로(묶음 · 결함 심기). */
    class Files(private val hide: Set<String> = emptySet(), private val override: Map<String, ByteArray> = emptyMap()) : BakeFiles {
        override fun read(path: String): ByteArray? {
            if (path in hide) return null
            override[path]?.let { return it }
            return File(bakeRoot, path).takeIf { it.isFile }?.readBytes()
        }

        override fun readHalo(fileName: String): ByteArray? = File(haloRoot, fileName).takeIf { it.isFile }?.readBytes()
    }

    val files = Files()
    val library: BakeLibrary by lazy { BakeLibrary.load(files) }
    val goldens: GoldenSet by lazy { GoldenSet.parse(File(bakeRoot, "golden/golden.json").readText()) }

    fun goldenBytes(g: Golden): ByteArray = File(bakeRoot, "golden/${g.file}").readBytes()
}
