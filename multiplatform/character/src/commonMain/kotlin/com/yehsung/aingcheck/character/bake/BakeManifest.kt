// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (Baker 가 쓰는 manifest.json `bake` 칸 — 설계 F §3.5 상위집합 · G §8-12·§8-13 알파 계약)
package com.yehsung.aingcheck.character.bake

import com.yehsung.aingcheck.character.bake.BakeJson.arr
import com.yehsung.aingcheck.character.bake.BakeJson.dbl
import com.yehsung.aingcheck.character.bake.BakeJson.doubles
import com.yehsung.aingcheck.character.bake.BakeJson.int
import com.yehsung.aingcheck.character.bake.BakeJson.ints
import com.yehsung.aingcheck.character.bake.BakeJson.obj
import com.yehsung.aingcheck.character.bake.BakeJson.opt
import com.yehsung.aingcheck.character.bake.BakeJson.req
import com.yehsung.aingcheck.character.bake.BakeJson.str
import com.yehsung.aingcheck.character.bake.BakeJson.strs
import com.yehsung.aingcheck.core.rules.character.CharacterManifest

/**
 * 구운 아잉이 한 마감의 매니페스트 = 기존 2D 매니페스트(W1-c [CharacterManifest], legacy 2칸 스프라이트) + `bake` 확장.
 * 기존 디코더는 `bake` 를 모르는 키로 무시한다(F §3.5). 이 타입은 W1-c 디코드를 **그대로 지난 뒤** `bake` 만 따로 읽는다(§8-1 마지막 줄).
 */
class BakedManifest(
    /** 기존 형식 그대로(W1-c 검증 통과). `bake` 를 못 읽어도 이것만으로 legacy 2칸 스프라이트가 선다. */
    val legacy: CharacterManifest,
    /** `bake` 확장. 없거나 모르는 큰 판(`format` > [SUPPORTED_FORMAT])이면 null → legacy 로 내려간다(F §7). */
    val bake: BakeExtension?,
    /** `bake` 를 버린 이유(시험·로그용). 읽었으면 null. */
    val bakeRejected: String?,
) {
    /** 서버 · 카탈로그 id(`aing_gold` — 파일 id `aing-gold` 는 밑줄 금지 문법이라 `bake.characterId` 에 둔다). legacy 만이면 파일 id. */
    val characterId: String get() = bake?.characterId ?: legacy.id

    companion object {
        /** 이 재생기가 아는 굽기 형식. */
        const val SUPPORTED_FORMAT = 1

        /** manifest.json 글자 → 매니페스트. legacy 가 W1-c 검증을 못 넘으면 W1-c 예외 그대로 던진다(카탈로그가 그 하나만 건너뛴다). */
        fun decode(text: String): BakedManifest {
            val legacy = CharacterManifest.decode(text)
            val root = BakeJson.parse(text)
            val bakeElement = root.opt("bake") ?: return BakedManifest(legacy, null, "bake 칸이 없다")
            val bakeObject = bakeElement.obj()
            val format = bakeObject.opt("format")?.int() ?: return BakedManifest(legacy, null, "bake.format 이 없다")
            if (format > SUPPORTED_FORMAT) return BakedManifest(legacy, null, "모르는 굽기 형식 $format(아는 판 $SUPPORTED_FORMAT)")
            return try {
                BakedManifest(legacy, BakeExtension.decode(bakeObject), null)
            } catch (e: BakeFormatException) {
                BakedManifest(legacy, null, "bake 모양이 틀렸다: ${e.message}")
            }
        }
    }
}

/** 단(tier) 하나 — S(오버레이 2x) · L(3x, Android 미리보기) · U(울트라). */
data class BakeTier(
    val name: String,
    val cellsFile: String,
    val pages: List<String>,
    val viewportWidth: Int,
    val viewportHeight: Int,
    val bodyPxMedian: Int,
    val cellCount: Int,
)

/** 후광(금 · 무지개) — 굽지 않고 원본 PNG 36칸을 런타임 2D 층으로 쓴다(F §3.6). */
data class BakeHalo(
    val cellFiles: List<String>,
    val centerUnits: List<Double>,
    val sideOverBodyHeight: Double,
    val restBandDeg: Double,
    val sideRestDeg: Double,
    val yawStepDeg: Int,
)

/** 디코드 클램프(G §8-13): 프리멀티 페이지를 디코드한 뒤 채널마다 `c := min(c, table[A])`(A = 0 → 0). */
class DecodeClampTable(val table: IntArray) {
    init {
        require(table.size == 256) { "클램프 표는 256칸이다: ${table.size}" }
        require(table[0] == 0) { "table[0] 은 0 이어야 한다(알파 0 자리의 코덱 빛을 지운다)" }
    }
}

class BakeExtension(
    val format: Int,
    val characterId: String,
    /** `standard` · `gold` · `rainbow`. */
    val finish: String,
    val quadHalfUnits: Double,
    /** 페이지 파일 이름(칸의 `page` = 이 목록의 번호). */
    val pages: List<String>,
    val tiers: List<BakeTier>,
    val halo: BakeHalo?,
    val clamp: DecodeClampTable,
    /** 역할별 알파: pages · glyph = premultiplied, legacy = straight. */
    val pagesAlpha: String,
    val legacyPivotX: Int,
    val legacyPivotY: Int,
    val cameraPath: String,
    val motionPath: String,
    val particlesPath: String,
    val glyphPath: String,
) {
    fun tier(name: String): BakeTier? = tiers.firstOrNull { it.name == name }

    companion object {
        fun decode(o: kotlinx.serialization.json.JsonObject): BakeExtension {
            val alpha = o.req("alpha").obj()
            val clampObj = alpha.req("decodeClamp").obj()
            val table = clampObj.req("table").ints().toIntArray()
            if (table.size != 256 || table[0] != 0) throw BakeFormatException("decodeClamp.table 이 256칸 · table[0]=0 이 아니다")
            val pagesAlpha = alpha.req("pages").str()
            if (pagesAlpha != "premultiplied") throw BakeFormatException("페이지 알파가 premultiplied 가 아니다: $pagesAlpha")
            val quadOrder = o.opt("quadOrder")?.str() ?: "TL,TR,BR,BL"
            if (quadOrder != "TL,TR,BR,BL") throw BakeFormatException("모르는 quadOrder: $quadOrder")
            val tiers = o.req("tiers").arr().map { t ->
                val to = t.obj()
                val vp = to.req("viewport").ints()
                if (vp.size != 2) throw BakeFormatException("tier.viewport 는 [w, h]")
                BakeTier(
                    name = to.req("name").str(),
                    cellsFile = to.req("cellsFile").str(),
                    pages = to.req("pages").strs(),
                    viewportWidth = vp[0],
                    viewportHeight = vp[1],
                    bodyPxMedian = to.req("bodyPxMedian").int(),
                    cellCount = to.req("cells").int(),
                )
            }
            val halo = o.opt("halo")?.obj()?.let { h ->
                BakeHalo(
                    cellFiles = h.req("cellFiles").strs(),
                    centerUnits = h.req("centerUnits").doubles(),
                    sideOverBodyHeight = h.req("sideOverBodyHeight").dbl(),
                    restBandDeg = h.req("restBandDeg").dbl(),
                    sideRestDeg = h.req("sideRestDeg").dbl(),
                    yawStepDeg = h.req("yawStepDeg").int(),
                )
            }
            val pivot = o.req("legacyPivot").obj()
            return BakeExtension(
                format = o.req("format").int(),
                characterId = o.req("characterId").str(),
                finish = o.req("finish").str(),
                quadHalfUnits = o.req("quadHalfUnits").dbl(),
                pages = o.req("pages").strs(),
                tiers = tiers,
                halo = halo,
                clamp = DecodeClampTable(table),
                pagesAlpha = pagesAlpha,
                legacyPivotX = pivot.req("x").int(),
                legacyPivotY = pivot.req("y").int(),
                cameraPath = o.req("camera").str(),
                motionPath = o.req("motion").str(),
                particlesPath = o.req("particles").str(),
                glyphPath = o.req("glyph").str(),
            )
        }
    }
}
