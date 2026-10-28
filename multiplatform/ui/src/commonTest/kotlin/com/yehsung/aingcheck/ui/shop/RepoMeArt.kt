// 원본: 없음 — 시험 그림 창구(앱의 Compose 리소스 경로 → 저장소 원본 PNG, Gradle Sync 규칙과 같은 표).
//
// 스냅숏이 첫 장부터 그림을 갖게 한다(비동기 0). 경로 표는 ui/build.gradle.kts `aingcheckSyncCharacterArt`(+ 이 갈래 패치 0001 의 기계 그림)와 같다:
//   files/characters/<id>/portrait-<표정>.png → Sources/check/Characters/<id>/portrait-<표정>.png
//                                               (아잉 가족 다섯은 Sources/check/Resources/<id>-<표정>.png)
//   files/art/<이름>.png                     → Sources/CheckMobileKit/Resources/Art/<이름>.png
//   files/gacha/<이름>.png                   → Sources/CheckCore/Resources/GachaMachine/<이름>.png
// 바이트 읽기는 플랫폼 시험이 넘긴다(데스크톱 · Android 호스트 모두 java.io.File).
package com.yehsung.aingcheck.ui.shop

import androidx.compose.ui.graphics.ImageBitmap
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.compose.resources.decodeToImageBitmap

class RepoMeArt(private val readRepoBytes: (String) -> ByteArray?) : MeArtSource {
    private val cache = HashMap<String, ImageBitmap?>()

    @OptIn(ExperimentalResourceApi::class)
    override fun peek(path: String): ImageBitmap? = cache.getOrPut(path) {
        repoPath(path)?.let(readRepoBytes)?.decodeToImageBitmap()
    }

    override suspend fun load(path: String): ImageBitmap? = peek(path)

    /** 이 경로가 저장소에 있는가(원본이 없으면 시험이 알아야 한다). */
    fun has(path: String): Boolean = peek(path) != null

    companion object {
        private val aingFamily = setOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco")
        private val portrait = Regex("^files/characters/([a-z0-9_]+)/portrait-([a-z]+)\\.png$")

        fun repoPath(resourcePath: String): String? {
            portrait.matchEntire(resourcePath)?.let { m ->
                val (id, expression) = m.destructured
                return if (id in aingFamily) "Sources/check/Resources/$id-$expression.png" else "Sources/check/Characters/$id/portrait-$expression.png"
            }
            if (resourcePath.startsWith("files/art/")) return "Sources/CheckMobileKit/Resources/Art/" + resourcePath.removePrefix("files/art/")
            if (resourcePath.startsWith("files/gacha/")) return "Sources/CheckCore/Resources/GachaMachine/" + resourcePath.removePrefix("files/gacha/")
            return null
        }
    }
}
