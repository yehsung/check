// 완료 기준 ④ 의 "git 에 사본 0": 캐릭터·루비·무대 그림과 매니페스트는 맥 원본(Sources/…)에만 있고 multiplatform/ 아래에는 바이트가 같은
// 파일이 하나도 없다(빌드 폴더 제외 — Gradle Sync 의 출력은 build/ 아래다). 이름을 바꿔 들여놓아도 내용으로 잡는다.
package com.yehsung.aingcheck.ui.components

import java.io.File
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertTrue

class CharacterArtNoCopyTest {
    private fun sha(f: File) = MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }

    private fun originals(repo: File): List<File> {
        val chars = File(repo, "Sources/check/Characters").walkTopDown().filter { it.isFile && (it.name == "manifest.json" || it.name.startsWith("portrait-")) }
        val aing = File(repo, "Sources/check/Resources").listFiles().orEmpty()
            .filter { f -> CharacterArt.portraitIds.any { id -> f.name == "$id-neutral.png" || f.name == "$id-negative.png" } }
        val art = File(repo, "Sources/CheckMobileKit/Resources/Art").listFiles().orEmpty()
            .filter { it.name.startsWith("ruby") || it.name.startsWith("stage-") }
        return (chars.toList() + aing + art).sortedBy { it.path }
    }

    @Test
    fun noCopyOfCharacterArtUnderMultiplatform() {
        val repo = DesktopSnapshots.repoRoot
        val src = originals(repo)
        // 초상 9×2 + 매니페스트 6 + 루비 3 + 무대 6 = 33
        assertTrue(src.size == 33, "원본 그림을 ${src.size}개 찾았다(33 이어야 한다): ${src.map { it.name }}")
        val copies = findCopies(DesktopSnapshots.mpRoot, src.associateBy { sha(it) })
        assertTrue(copies.isEmpty(), "multiplatform/ 에 원본 그림 사본이 있다(Gradle Sync 로 읽어야 한다):\n" + copies.joinToString("\n"))
    }

    private fun findCopies(root: File, hashes: Map<String, File>): List<String> = root.walkTopDown()
        .onEnter { it == root || (it.name != "build" && it.name != ".gradle" && it.name != ".kotlin" && it.name != "spikes") }
        .filter { it.isFile && (it.name.endsWith(".png") || it.name.endsWith(".json")) }
        .mapNotNull { f -> hashes[sha(f)]?.let { "${f.relativeTo(root)} = ${it.name}" } }
        .toList()

    /** 내용 대조가 실제로 잡는다(심은 결함): 원본 한 장의 바이트가 이름만 바꿔 들어오면 걸린다. */
    @Test
    fun plantedCopyWouldBeCaught() {
        val repo = DesktopSnapshots.repoRoot
        val one = File(repo, "Sources/check/Characters/fox/portrait-neutral.png")
        val tree = File(DesktopSnapshots.outDir().parentFile, "planted-tree").apply { deleteRecursively() }
        File(tree, "ui/src/commonMain/composeResources/drawable/totally_not_a_fox.png").apply { parentFile.mkdirs(); writeBytes(one.readBytes()) }
        File(tree, "ui/build/generated/files/characters/fox/portrait-neutral.png").apply { parentFile.mkdirs(); writeBytes(one.readBytes()) }
        val found = findCopies(tree, originals(repo).associateBy { sha(it) })
        assertTrue(found.size == 1 && found[0].startsWith("ui/src/"), "심은 사본(이름 바꿈)만 잡고 build/ 의 Sync 출력은 넘겨야 한다: $found")
        tree.deleteRecursively()
    }
}
