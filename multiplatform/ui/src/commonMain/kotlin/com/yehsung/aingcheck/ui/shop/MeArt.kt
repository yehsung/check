// 원본: Sources/CheckMobileKit/Components/MobileArt.swift @ 3bd04bd (루비 · 초상 · 무대 그림 창구)
// 원본: Sources/CheckCore/GachaMachine/GachaMachineModel.swift @ 3bd04bd (GachaMachineArtBundle — 기계 그림 다섯 장)
//
// 상점 · 뽑기 · 미션 화면의 그림 창구. 화면은 경로(Compose 리소스 files/…)로 그림을 묻고, 창구가 풀어 준다.
//  - 앱: [ResourceMeArt] — CharacterArt(Res, Gradle Sync 로 실린 맥 원본)에서 풀고 프로세스 안에 쥔다.
//  - 시험: 같은 경로를 저장소 원본 PNG 로 곧바로 주는 창구를 [LocalMeArt] 로 꽂는다(스냅숏이 첫 장부터 그림을 갖는다 — 비동기 0).
// 기계 그림(files/gacha/…)은 ui Gradle Sync 패치(조정자 — patches/0001)가 싣는다. 그 전 빌드는 null 이라 기계가 벡터로 그린다.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalDensity
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineArt

/** 그림 창구. [peek] 은 이미 풀어 둔 것(없으면 null — 바로 답한다), [load] 는 풀어서 준다(없으면 null — 이 빌드에 그림이 없다). */
interface MeArtSource {
    fun peek(path: String): ImageBitmap?
    suspend fun load(path: String): ImageBitmap?
}

/** 앱 창구: Compose 리소스에서 풀고 쥔다(같은 경로는 한 번만 푼다). */
object ResourceMeArt : MeArtSource {
    private val cache = HashMap<String, ImageBitmap>()
    private val missing = HashSet<String>()

    override fun peek(path: String): ImageBitmap? = cache[path]

    override suspend fun load(path: String): ImageBitmap? {
        cache[path]?.let { return it }
        if (path in missing) return null
        val image = CharacterArt.decode(path)
        if (image != null) cache[path] = image else missing += path
        return image
    }
}

val LocalMeArt = staticCompositionLocalOf<MeArtSource> { ResourceMeArt }

/** 경로 하나의 그림(처음 한 번은 null 일 수 있다 — 시험 창구는 바로 준다). */
@Composable
fun rememberMeArt(path: String): ImageBitmap? {
    val source = LocalMeArt.current
    val image by produceState(source.peek(path), path, source) { if (value == null) value = source.load(path) }
    return image
}

object MeArtPaths {
    fun portrait(id: String, expression: CharacterExpression = CharacterExpression.Neutral): String = CharacterArt.portraitPath(id, expression)
    fun ruby(pointSize: Float, density: Float): String = CharacterArt.rubyPath(pointSize, density)
    fun machine(name: String): String = GachaMachineArt.resourcePath(name)

    /** 이 빌드가 초상을 싣는 캐릭터(모르는 id 는 그림을 지어내지 않는다 — 자리표시). */
    fun isKnown(id: String): Boolean = id in CharacterArt.portraitIds
}

@Composable
fun rememberPortrait(id: String, expression: CharacterExpression = CharacterExpression.Neutral): ImageBitmap? =
    if (MeArtPaths.isKnown(id)) rememberMeArt(MeArtPaths.portrait(id, expression)) else null

@Composable
fun rememberRuby(pointSize: Float): ImageBitmap? = rememberMeArt(MeArtPaths.ruby(pointSize, LocalDensity.current.density))

/** 기계 그림 다섯 장(빠진 칸은 null — 벡터로 그린다). */
@Composable
fun rememberMachineArt(): GachaMachineArt {
    val names = GachaMachineArt.resourceNames
    val body = rememberMeArt(MeArtPaths.machine(names[0]))
    val knob = rememberMeArt(MeArtPaths.machine(names[1]))
    val capsule = rememberMeArt(MeArtPaths.machine(names[2]))
    val gold = rememberMeArt(MeArtPaths.machine(names[3]))
    val cap = rememberMeArt(MeArtPaths.machine(names[4]))
    return GachaMachineArt(body, knob, capsule, gold, cap)
}
