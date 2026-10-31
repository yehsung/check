// 원본: Tests/checkTests/GoldenExport/rummy/GoldenExportRummyTableLayout.swift · GoldenExportRummyTableEdit.swift · GoldenExportRummyRackLayout.swift(골든 생성기) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.rules.renju.bool
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** 판 배치 · 판 편집 · 받침대가 Swift 와 비트로 같다(모든 기기가 같은 판을 그린다). */
class RummyLayoutGoldenTest {
    private val t = RummyGoldenText

    private fun List<JsonObject>.ofKind(kind: String) = filter { it.string("kind_") == kind }

    // MARK: table-layout

    @Test
    fun tableLayoutMatchesSwift() {
        val golden = Golden.load("rummy/table-layout")
        val constants = golden.cases.ofKind("constants").single()
        assertEquals(constants.int("canvasWidth").toLong(), RummyTableLayout.canvasWidth)
        assertEquals(constants.int("canvasHeight").toLong(), RummyTableLayout.canvasHeight)
        assertEquals(constants.int("tileWidth").toLong(), RummyTableLayout.tileWidth)
        assertEquals(constants.int("tileHeight").toLong(), RummyTableLayout.tileHeight)
        assertEquals(constants.int("grid").toLong(), RummyTableLayout.grid)
        assertEquals(constants.int("clearance").toLong(), RummyTableLayout.clearance)

        val places = golden.cases.ofKind("place")
        assertTrue(places.size >= 40, "place 표가 잘렸다: ${places.size}")
        for (case in places) {
            val id = case.string("id")
            val sets = t.sets(case.string("sets"))
            val layout = case.optString("layout")?.let { RummyLayout(t.points(it)) }
            assertEquals(case.string("points"), t.pointsText(RummyTableLayout.place(sets, layout)), id)
            assertEquals(case.string("sanitized"), t.pointsText(RummyTableLayout.sanitize(layout, sets.size)), id)
            assertEquals(case.string("frames"), t.rectsText(RummyTableLayout(sets, layout).frames), id)
        }

        val spots = golden.cases.ofKind("spot")
        assertTrue(spots.size >= 100, "spot 표가 잘렸다: ${spots.size}")
        for (case in spots) {
            val id = case.string("id")
            val among = t.rects(case.string("among"))
            val point = t.point(case.string("point"))
            val tiles = case.int("tiles")
            assertEquals(case.string("firstFree"), t.pointText(RummyTableLayout.firstFree(tiles, among)), id)
            assertEquals(case.string("snap"), t.pointText(RummyTableLayout.snap(point, tiles, among)), id)
            assertEquals(case.optString("freeSpot"), RummyTableLayout.freeSpot(point, tiles, among)?.let { t.pointText(it) }, id)
            assertEquals(case.string("refit"), t.pointText(RummyTableLayout.refit(point, tiles, among)), id)
            assertEquals(case.string("clampInside"), t.pointText(RummyTableLayout.clampInside(point, tiles)), id)
            assertEquals(case.bool("clear"), RummyTableLayout.isClear(RummyTableLayout.frame(point, tiles), among), id)
        }

        for (case in golden.cases.ofKind("rect")) {
            val id = case.string("id")
            val a = t.rect(case.string("a"))
            val b = t.rect(case.string("b"))
            val p = t.point(case.string("p"))
            assertEquals(case.bool("fits"), RummyTableLayout.fits(a), id)
            assertEquals(case.bool("overlaps"), RummyTableLayout.overlaps(a, b), id)
            assertEquals(case.bool("contains"), a.contains(p), id)
            assertEquals(case.bool("accepts"), RummyTableLayout.acceptsWire(p.x, p.y), id)
        }

        val shown = RummyTableLayout(listOf("A1 A2 A3", "B7 C7 D7", "C9 C10 C11 C12", "A5 B5 C5 D5 ", "J A5 A6").map { t.faces(it) }, null)
        for (case in golden.cases.ofKind("query")) {
            val id = case.string("id")
            val p = t.point(case.string("p"))
            assertEquals(case.optInt("setIndex"), shown.setIndex(p), id)
            assertEquals(case.optString("frame"), shown.frame(case.int("set"))?.let { t.rectText(it) }, id)
            assertEquals(case.optString("tileFrame"), shown.tileFrame(case.int("set"), case.int("tile"))?.let { t.rectText(it) }, id)
            assertEquals(case.string("snap"), t.pointText(shown.snap(p, 3, case.optInt("excluding"))), id)
        }
    }

    // MARK: table-edit

    @Test
    fun tableEditMatchesSwift() {
        val golden = Golden.load("rummy/table-edit")
        val constants = golden.cases.ofKind("constants").single()
        assertEquals(constants.int("attachGap").toLong(), RummyTableEdit.attachGap)
        assertEquals(constants.int("attachRise").toLong(), RummyTableEdit.attachRise)

        for (case in golden.cases.ofKind("split")) {
            val count = case.int("count")
            val mask = case.int("mask")
            val removed = (0 until count).filter { mask and (1 shl it) != 0 }.toSet()
            val pieces = RummyTableEdit.split(count, t.point(case.string("point")), removed)
            assertEquals(case.string("pieces"), pieces.joinToString(" ") { "${it.range.first}..${it.range.last + 1}@${t.pointText(it.point)}" }, case.string("id"))
        }
        assertEquals(255, golden.cases.ofKind("split").size)

        for (case in golden.cases.ofKind("pick")) {
            val range = RummyTableEdit.pickRange(case.int("count"), case.int("pressed"))
            val lo = if (range.isEmpty()) 0 else range.first
            val hi = if (range.isEmpty()) 0 else range.last + 1
            assertEquals(case.int("lo") to case.int("hi"), lo to hi, case.string("id"))
        }

        for (case in golden.cases.ofKind("attached")) {
            val side = RummyAttachSide.entries.first { it.rawValue == case.string("side") }
            assertEquals(case.string("point"), t.pointText(RummyTableEdit.attachedPoint(ep(300, 120), side, case.int("count"))), case.string("id"))
        }

        var hits = 0
        val attachments = golden.cases.ofKind("attachment")
        assertTrue(attachments.size >= 110, "attachment 표가 잘렸다: ${attachments.size}")
        for (case in attachments) {
            val sets = case.string("sets").split('|').map { t.faces(it) }
            val sides = case.string("sides").split(',').map { name -> RummyAttachSide.entries.first { it.rawValue == name } }
            val hit = RummyTableEdit.attachment(t.faces(case.string("block")), t.rect(case.string("frame")), sets, t.rects(case.string("frames")), sides)
            if (hit != null) hits += 1
            assertEquals(case.optString("hit"), hit?.let { "${it.set}:${it.side.rawValue}" }, case.string("id"))
        }
        assertTrue(hits >= 20, "붙기가 거의 안 일어난다 — 표가 규칙을 못 건드린다($hits)")

        val insertions = golden.cases.ofKind("insertion")
        assertTrue(insertions.size >= 110)
        assertTrue(insertions.count { it.bool("fits") } >= 40, "맞는 자리가 거의 없다 — 표가 자리 고르기를 못 건드린다")
        for (case in insertions) {
            val got = RummyTableEdit.insertionIndex(t.faces(case.string("block")), t.faces(case.string("meld")), case.int("preferred"))
            assertEquals(case.int("index"), got.index, case.string("id"))
            assertEquals(case.bool("fits"), got.fits, case.string("id"))
        }

        val settles = golden.cases.ofKind("settle")
        assertTrue(settles.size >= 90)
        for (case in settles) {
            val points = RummyTableEdit.settle(t.rects(case.string("frames")), case.int("index"), case.int("grown"))
            assertEquals(case.string("points"), t.pointsText(points), case.string("id"))
        }
    }

    // MARK: rack-layout

    private fun layoutOf(text: String): RummyRackLayout {
        val layout = RummyRackLayout()
        if (text.isNotEmpty()) {
            for (entry in text.split(' ')) {
                val (id, slot) = entry.split('@')
                layout.set(listOf(id.toInt()), t.slot(slot))
            }
        }
        return layout
    }

    @Test
    fun rackLayoutMatchesSwift() {
        val golden = Golden.load("rummy/rack-layout")
        val constants = golden.cases.ofKind("constants").single()
        assertEquals(constants.int("halfColumnsPerRow"), RummyRackLayout.halfColumnsPerRow)
        assertEquals(constants.int("baseRows"), RummyRackLayout.baseRows)
        assertEquals(constants.int("tileSpan"), RummyRackLayout.tileSpan)

        val inserts = golden.cases.ofKind("insert")
        assertTrue(inserts.size >= 36)
        for (case in inserts) {
            val layout = layoutOf(case.string("seedLayout"))
            for ((index, step) in case.array("steps").strings().withIndex()) {
                val (op, expected) = step.split(" => ")
                val (ids, wanted) = op.split(' ')
                layout.insert(t.ints(ids), t.slot(wanted))
                val got = "${t.layout(layout)} rows=${layout.rowCount} chunks=${layout.chunks.joinToString(";") { t.ids(it) }} order=${t.ids(layout.readingOrder)}"
                assertEquals(expected, got, "${case.string("id")} 단계 $index")
            }
        }

        for (case in golden.cases.ofKind("free")) {
            val id = case.string("id")
            val layout = layoutOf(case.string("layout"))
            val slot = t.slot(case.string("slot"))
            val tiles = case.int("tiles")
            val excluding = t.ints(case.string("excluding")).toSet()
            assertEquals(case.bool("isFree"), layout.isFree(slot, tiles, excluding), id)
            assertEquals(case.string("nearest"), t.slotText(layout.nearestFree(slot, tiles, excluding)), id)
            assertEquals(case.string("end"), t.slotText(layout.endSlot(tiles, excluding)), id)
            assertEquals(case.optInt("covering"), layout.tile(slot), id)
            assertEquals(case.int("rows"), layout.rowCount, id)
            assertEquals(case.string("order"), t.ids(layout.readingOrder), id)
            assertEquals(case.string("chunks"), layout.chunks.joinToString(";") { t.ids(it) }, id)
        }

        for (case in golden.cases.ofKind("grouped")) {
            val id = case.string("id")
            val text = case.string("units")
            val units = if (text.isEmpty()) emptyList() else text.split(';').map { t.ints(it) }
            assertEquals(case.string("grouped"), t.layout(RummyRackLayout.grouped(units, case.int("gap"))), id)
            assertEquals(case.string("groupedDefault"), t.layout(RummyRackLayout.grouped(units)), id)
            assertEquals(case.string("packed"), t.layout(RummyRackLayout.packed(units.flatten())), id)
        }

        for (case in golden.cases.ofKind("sort")) {
            val tiles = t.faces(case.string("faces")).mapIndexed { index, face -> RummyTile(index, face) }
            val mode = RummyRackSort.valueOf(case.string("mode"))
            val units = RummyRackLayout.sortUnits(tiles, mode)
            assertEquals(case.string("units"), units.joinToString("|") { unit -> unit.joinToString(" ") { "${it.id}:${it.face.text}" } }, case.string("id"))
        }

        val melds = golden.cases.ofKind("melds")
        assertTrue(melds.size >= 30)
        var withMelds = 0
        for (case in melds) {
            val id = case.string("id")
            val rows = case.string("entries").split(' ').map {
                val (face, slot) = it.split('@')
                RummyRackEntry(t.face(face), t.slot(slot))
            }
            val tableText = case.string("table")
            val editor = RummyTurnEditor(
                table = if (tableText.isEmpty()) emptyList() else tableText.split('|').map { t.faces(it) },
                rack = rows.map { it.face },
                initialDone = case.bool("initialDone"),
                rackEntries = rows,
            )
            if (editor.rackMelds.isNotEmpty()) withMelds += 1
            assertEquals(case.string("melds"), editor.rackMelds.joinToString(";") { "${t.ids(it.tileIDs)}:${it.kind.rawValue}:${it.points}" }, id)
            assertEquals(case.int("points"), editor.rackMeldPoints, id)
            assertEquals(case.optString("plan"), editor.initialPlanPoints?.let { "${it.table},${it.rack}" }, id)
            assertEquals(case.string("core"), t.core(editor), id)
        }
        assertTrue(withMelds >= 5, "맞는 덩어리가 거의 없다 — 표가 규칙을 못 건드린다($withMelds)")
        assertTrue(golden.cases.none { it["kind_"] is JsonNull })
    }
}
