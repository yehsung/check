// 원본: Tests/checkTests/GoldenExport/rummy/GoldenRummySupport.swift @ 1a5eeca6 (같은 표기를 같은 이름으로 — 형식 정본: contract/README.md §2)
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFnv1a64
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** 골든 칸의 한 줄 글자 표기(생성기 GoldenRummyText 와 같다). 시험에서도 면·점을 이것으로 쓴다. */
internal object RummyGoldenText {
    fun face(text: String): RummyFace = RummyFace.of(text) ?: error("시험 면 오타: $text")

    fun faces(text: String): List<RummyFace> = text.split(' ').filter { it.isNotEmpty() }.map { face(it) }

    fun text(faces: List<RummyFace>): String = faces.joinToString(" ") { it.text }

    /** "A1 A2|B1" → 묶음 목록(글자가 비면 빈 목록). */
    fun sets(text: String): List<List<RummyFace>> = if (text.isEmpty()) emptyList() else text.split('|').map { faces(it) }

    fun setsText(sets: List<List<RummyFace>>): String = sets.joinToString("|") { text(it) }

    fun point(text: String): RummyPoint {
        val (x, y) = text.split(',')
        return RummyPoint(x.toLong(), y.toLong())
    }

    fun pointText(p: RummyPoint): String = "${p.x},${p.y}"

    /** "x,y - x,y" → 점 목록(빈 칸 null). */
    fun points(text: String): List<RummyPoint?> =
        if (text.isEmpty()) emptyList() else text.split(' ').map { if (it == "-") null else point(it) }

    fun pointsText(points: List<RummyPoint?>): String = points.joinToString(" ") { if (it == null) "-" else pointText(it) }

    fun rect(text: String): RummyRect {
        val (x, y, w, h) = text.split(',')
        return RummyRect(x.toLong(), y.toLong(), w.toLong(), h.toLong())
    }

    fun rectText(r: RummyRect): String = "${r.x},${r.y},${r.width},${r.height}"

    fun rects(text: String): List<RummyRect> = if (text.isEmpty()) emptyList() else text.split(' ').map { rect(it) }

    fun rectsText(rects: List<RummyRect>): String = rects.joinToString(" ") { rectText(it) }

    fun slot(text: String): RummyRackSlot {
        val (row, col) = text.split(',')
        return RummyRackSlot(row.toInt(), col.toInt())
    }

    fun slotText(s: RummyRackSlot): String = "${s.row},${s.halfCol}"

    fun ints(text: String): List<Int> = if (text.isEmpty()) emptyList() else text.split(',').map { it.toInt() }

    fun ids(values: List<Int>): String = values.joinToString(",")

    fun target(text: String): RummyDropTarget {
        val parts = text.split(':')
        return when (parts[0]) {
            "rack" -> RummyDropTarget.Rack(parts.getOrNull(1)?.toInt())
            "meld" -> RummyDropTarget.Meld(parts[1].toInt(), parts.getOrNull(2)?.toInt())
            "new" -> RummyDropTarget.NewMeld
            "at" -> RummyDropTarget.NewMeldAt(point(parts[1]))
            "slot" -> RummyDropTarget.RackSlot(slot(parts[1]))
            else -> error("모르는 놓는 곳: $text")
        }
    }

    fun plan(p: RummyDropPlan): String = when (p) {
        RummyDropPlan.Rack -> "rack"
        is RummyDropPlan.Attach -> "attach:${p.set}:${p.side.rawValue}"
        is RummyDropPlan.Insert -> "insert:${p.set}:${p.index}"
        is RummyDropPlan.NewSet -> "new:${pointText(p.point)}"
    }

    fun preview(p: RummyDropPreview?): String {
        if (p == null) return "nil"
        val l = p.landing ?: return "${plan(p.plan)} landing=-"
        return "${plan(p.plan)} landing=${l.set}|${text(l.faces)}|${rectText(l.frame)}|${l.blockStart}|${if (l.valid) 1 else 0}"
    }

    /** 받침대 자리 글자: id 오름차순 "id@r,c". */
    fun layout(l: RummyRackLayout): String = l.slots.keys.sorted().joinToString(" ") { "$it@${slotText(l.slots.getValue(it))}" }

    fun core(e: RummyTurnEditor): String {
        val melds = e.melds.indices.joinToString(" | ") { set ->
            e.melds[set].joinToString(" ") { "${it.id}:${it.face.text}" } + "@${pointText(e.points[set])}"
        }
        val rackLayout = e.rackLayout
        val rack = e.rack.joinToString(" ") { "${it.id}:${it.face.text}@${slotText(rackLayout.slot(it.id)!!)}" }
        return "T $melds R $rack reason=${e.reason.rawValue} submit=${bit(e.canSubmit)} changed=${bit(e.isChanged)}" +
            " layout=${bit(e.isLayoutChanged)} init=${e.initialPoints} played=${e.playedCount} rows=${rackLayout.rowCount}"
    }

    fun extra(e: RummyTurnEditor): String {
        val out = ArrayList<String>()
        out.add("melds=" + e.rackMelds.joinToString(";") { "${ids(it.tileIDs)}:${it.kind.rawValue}:${it.points}" })
        out.add("rackPts=${e.rackMeldPoints}")
        val plan = e.initialPlanPoints
        out.add(if (plan != null) "plan=${plan.table},${plan.rack}" else "plan=-")
        out.add("restored=" + e.restoredRackEntries.joinToString(" ") { "${it.face.text}@${slotText(it.slot)}" })
        out.add("chunks=" + e.rackLayout.chunks.joinToString(";") { ids(it) })
        out.add("chains=" + e.rack.joinToString(";") { "${it.id}>${ids(e.rackChain(it.id))}" })
        out.add(
            "picks=" + e.melds.flatten().joinToString(";") {
                "${it.id}>${ids(e.meldChunk(it.id))}/${ids(e.meldPick(it.id))}/${ids(e.meldPick(it.id, fromTileToEnd = true))}"
            },
        )
        out.add(
            "analysis=" + e.melds.indices.joinToString(";") { i ->
                val a = e.analysis(i)
                "${bit(a.valid)}:${a.kind?.rawValue ?: "-"}:${a.points?.toString() ?: "-"}"
            },
        )
        return out.joinToString(" ")
    }

    fun bit(flag: Boolean): Int = if (flag) 1 else 0

    /** FNV-1a 64(UTF-8 바이트를 하나씩 — 생성기 fnv 와 같다). */
    fun fnv(text: String): String {
        val hasher = GoldenFnv1a64()
        for (byte in text.encodeToByteArray()) hasher.add((byte.toInt() and 0xFF).toULong())
        return Golden.hex64Text(hasher.value)
    }

    /** 대본 시작(table·rack·initialDone·layout·rackOrder·rackEntries) → 편집기. */
    fun editor(case: JsonObject): RummyTurnEditor {
        fun opt(key: String): String? = (case[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
        val entries = opt("rackEntries")?.let { text ->
            if (text.isEmpty()) {
                emptyList()
            } else {
                text.split(' ').map {
                    val (face, slot) = it.split('@')
                    RummyRackEntry(face(face), slot(slot))
                }
            }
        }
        return RummyTurnEditor(
            table = sets(opt("table")!!),
            rack = faces(opt("rack")!!),
            initialDone = (case["initialDone"] as JsonPrimitive).content == "true",
            rackOrder = opt("rackOrder")?.let { faces(it) },
            tableLayout = opt("layout")?.let { RummyLayout(points(it)) },
            rackEntries = entries,
        )
    }
}

/** 시험 면 글자 줄임. */
internal fun ef(text: String): List<RummyFace> = RummyGoldenText.faces(text)

internal fun ep(x: Long, y: Long): RummyPoint = RummyPoint(x, y)
