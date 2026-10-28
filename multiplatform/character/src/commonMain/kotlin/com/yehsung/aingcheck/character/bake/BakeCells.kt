// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (BakeCell · BakeGrid.sorted · Baker 의 cells-<tier>.json)
package com.yehsung.aingcheck.character.bake

import com.yehsung.aingcheck.character.bake.BakeJson.arr
import com.yehsung.aingcheck.character.bake.BakeJson.dbl
import com.yehsung.aingcheck.character.bake.BakeJson.doubles
import com.yehsung.aingcheck.character.bake.BakeJson.int
import com.yehsung.aingcheck.character.bake.BakeJson.obj
import com.yehsung.aingcheck.character.bake.BakeJson.opt
import com.yehsung.aingcheck.character.bake.BakeJson.req
import com.yehsung.aingcheck.character.bake.BakeJson.str
import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3

/** 페이지 안의 픽셀 사각형(위-왼쪽 원점). */
data class PixelRect(val x: Int, val y: Int, val w: Int, val h: Int)

/** 감은 눈 패치: 패치 페이지의 사각형을 칸 좌표 `(atX, atY)` 에 **덮어쓰기(복사)** 로 얹는다(F §3.2-3). */
data class ClosedPatch(val page: Int, val rect: PixelRect, val atX: Int, val atY: Int)

/**
 * 구운 칸 하나. 키 = (몸 요 ψ, 시선 기울기 τ) — ψ + 면 얼굴이 화면 오른쪽(후광 칸과 같은 부호, `GoldAing.swift:63-70`).
 * [quad] 는 칸 렌더에서 몸 국소 네 점(피벗 ± h·r ± h·u, r·u ⟂ 칸 방향)을 투영한 **칸 픽셀 연속 좌표**(TL · TR · BR · BL).
 */
data class BakeCell(
    val id: String,
    val tier: String,
    val group: Group,
    val yawDeg: Int,
    val tiltDeg: Double,
    val page: Int,
    val rect: PixelRect,
    val quad: List<Vec2>,
    val pivot: Vec2,
    val closedPatch: ClosedPatch?,
) {
    enum class Group { rest, band, spin, ultra }

    /** 몸 국소에서 본 카메라 방향(단위벡터). */
    val direction: Vec3 = Angles.cellDirection(yawDeg.toDouble(), tiltDeg)

    companion object {
        /** Swift `BakeGrid.sorted` 순서: 무리(쉬는 < 띠 < 스핀 < 울트라) → 기울기 → 요. 칸 번호(동점 깨기)가 이 순서다. */
        val canonicalOrder: Comparator<BakeCell> = compareBy<BakeCell>({ it.group.ordinal }, { it.tiltDeg }, { it.yawDeg })
    }
}

/** cells-<tier>.json 한 장. */
class BakeCells(val tier: String, val pages: List<String>, val cells: List<BakeCell>) {
    private val byId: Map<String, BakeCell> = cells.associateBy { it.id }
    fun cell(id: String): BakeCell? = byId[id]

    companion object {
        fun decode(text: String): BakeCells {
            val o = BakeJson.parse(text)
            val format = o.req("format").int()
            if (format != BakedManifest.SUPPORTED_FORMAT) throw BakeFormatException("cells 형식 $format")
            val tier = o.req("tier").str()
            val pages = o.req("pages").arr().map { it.str() }
            val cells = o.req("cells").arr().map { e ->
                val c = e.obj()
                val rect = rectOf(c.req("rect"))
                val quad = c.req("quad").arr().map { p -> p.doubles().let { if (it.size != 2) throw BakeFormatException("quad 점은 [x, y]"); Vec2(it[0], it[1]) } }
                if (quad.size != 4) throw BakeFormatException("quad 는 네 점")
                val pivot = c.req("pivot").doubles().let { Vec2(it[0], it[1]) }
                val patch = c.opt("closedPatch")?.obj()?.let { p ->
                    val at = p.req("at").obj()
                    ClosedPatch(p.req("page").int(), rectOf(p.req("rect")), at.req("x").int(), at.req("y").int())
                }
                val groupName = c.req("group").str()
                val group = BakeCell.Group.entries.firstOrNull { it.name == groupName } ?: throw BakeFormatException("모르는 무리 $groupName")
                BakeCell(
                    id = c.req("id").str(),
                    tier = c.req("tier").str(),
                    group = group,
                    yawDeg = c.req("bodyYawDeg").int(),
                    tiltDeg = c.req("viewTiltDeg").dbl(),
                    page = c.req("page").int(),
                    rect = rect,
                    quad = quad,
                    pivot = pivot,
                    closedPatch = patch,
                )
            }
            return BakeCells(tier, pages, cells)
        }

        private fun rectOf(e: kotlinx.serialization.json.JsonElement): PixelRect {
            val r = e.obj()
            return PixelRect(r.req("x").int(), r.req("y").int(), r.req("w").int(), r.req("h").int())
        }
    }
}
