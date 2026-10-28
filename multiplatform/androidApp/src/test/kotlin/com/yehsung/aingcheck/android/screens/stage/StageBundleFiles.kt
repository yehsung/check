// 원본: 없음 (시험 도우미 — 굽기 설정 scripts/bake-aing/config.json `bundles.androidDefault` 를 조립 빌드와 같은 글롭 규칙으로 읽어 저장소 파일 가운데 Android 묶음만 보인다)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeFiles
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.nio.file.FileSystems

/**
 * Android 기본 묶음(앱 APK `assets/aing-bake/`)과 같은 파일 집합을 저장소에서 고른다. 조립 빌드(조정자 패치 01)도 같은 설정 · 같은 글롭 문법
 * (`*` 는 한 마디 안)으로 고르므로, 이 집합 = APK 에 실리는 집합이다(기기 시험 StageDeviceTest 가 설치된 APK 로 따로 잰다).
 */
object StageBundleFiles {
    val mpRoot: File = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다(aingcheck.test-seal)" })
    val repoRoot: File = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다" })
    val bakeRoot: File = File(mpRoot, "assets/aing-bake")
    val configFile: File = File(mpRoot, "scripts/bake-aing/config.json")

    /** 묶음: 굽기 뿌리 상대 경로 → 파일, 후광 이름 → 파일. */
    class Bundle(val bakeFiles: Map<String, File>, val haloFiles: Map<String, File>) {
        val totalBytes: Long get() = bakeFiles.values.sumOf { it.length() } + haloFiles.values.sumOf { it.length() }
        fun bytesWhere(pred: (String) -> Boolean): Long = bakeFiles.filterKeys(pred).values.sumOf { it.length() }
    }

    fun bundle(name: String = "androidDefault", extraAssetGlobs: List<String> = emptyList()): Bundle {
        val cfg = Json.parseToJsonElement(configFile.readText()).jsonObject.getValue("bundles").jsonObject.getValue(name).jsonObject
        val assetGlobs = cfg.getValue("assets").jsonArray.map { it.jsonPrimitive.content } + extraAssetGlobs
        val repoGlobs = cfg.getValue("repo").jsonArray.map { it.jsonPrimitive.content }
        val fs = FileSystems.getDefault()
        val matchers = assetGlobs.map { fs.getPathMatcher("glob:$it") }
        val bake = bakeRoot.walkTopDown().filter { it.isFile }.associateBy { it.relativeTo(bakeRoot).invariantSeparatorsPath }
            .filterKeys { rel -> matchers.any { m -> m.matches(fs.getPath(rel)) } }
            .toSortedMap()
        val halos = LinkedHashMap<String, File>()
        for (glob in repoGlobs) {
            val f = File(repoRoot, glob)
            val m = fs.getPathMatcher("glob:${f.name}")
            f.parentFile.listFiles().orEmpty().filter { it.isFile && m.matches(fs.getPath(it.name)) }.sortedBy { it.name }.forEach { halos[it.name] = it }
        }
        return Bundle(bake, halos)
    }

    /** 묶음만 보이는 [BakeFiles](없는 파일은 null — APK 자산과 같다). */
    class Files(private val bundle: Bundle) : BakeFiles {
        val reads = ArrayList<String>()
        override fun read(path: String): ByteArray? { reads += path; return bundle.bakeFiles[path]?.readBytes() }
        override fun readHalo(fileName: String): ByteArray? { reads += "halo/$fileName"; return bundle.haloFiles[fileName]?.readBytes() }
    }
}
