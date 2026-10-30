// 원본: Tests/checkTests/GoldenExport/duel/GoldenExportDuel.swift(생성기) · Sources/CheckCore/TetrisDuelStore.swift · TetrisDuelStoreGame.swift @ 1b8260d
// G §2-3 W2-e ② 대결 재개 골든 `duel/resume` 의 Kotlin 대조 — 같은 서버 행·같은 단계에서 Kotlin 스토어가 Swift 스토어와 같은 끝 상태를 낸다.
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelBoard
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelCell
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisPlayerRow
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

@OptIn(ExperimentalCoroutinesApi::class)
class TetrisDuelResumeGoldenTest {
    private val golden = Golden.load("duel/resume")
    private val json = Json { ignoreUnknownKeys = true }

    private val letters = "ijlostz"

    // MARK: 덤프 — Swift `GoldenExportDuel.dump` 와 같은 칸 · 같은 표기

    private fun bits(d: Double): JsonElement = JsonPrimitive(Golden.bitsText(d))
    private fun date(d: SwiftDate?): JsonElement = d?.let { bits(it.timeIntervalSince1970) } ?: JsonNull
    private fun str(s: String?): JsonElement = s?.let(::JsonPrimitive) ?: JsonNull
    private fun int(i: Int?): JsonElement = i?.let(::JsonPrimitive) ?: JsonNull
    private fun long(i: Long?): JsonElement = i?.let(::JsonPrimitive) ?: JsonNull
    private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(mapOf(*pairs))

    private fun cellsText(cells: List<List<TetrisDuelCell>>): String = cells.joinToString("/") { row ->
        row.joinToString("") { cell ->
            when (cell) {
                TetrisDuelCell.Empty -> "."
                TetrisDuelCell.Garbage -> "G"
                is TetrisDuelCell.Piece -> TetrisDuelBoard.letter(cell.piece).toString()
            }
        }
    }

    private fun gamePhase(p: TetrisGame.Phase): JsonObject = when (p) {
        TetrisGame.Phase.Ready -> obj("kind" to JsonPrimitive("ready"))
        TetrisGame.Phase.Running -> obj("kind" to JsonPrimitive("running"))
        is TetrisGame.Phase.LineClear -> obj("kind" to JsonPrimitive("lineClear"), "remainingBits" to bits(p.remaining))
        is TetrisGame.Phase.Are -> obj("kind" to JsonPrimitive("are"), "remainingBits" to bits(p.remaining))
        is TetrisGame.Phase.Over -> obj("kind" to JsonPrimitive("over"), "holdBits" to bits(p.hold))
        TetrisGame.Phase.Result -> obj("kind" to JsonPrimitive("result"))
    }

    private fun dump(store: TetrisDuelStore): JsonObject {
        val out = linkedMapOf<String, JsonElement>(
            "phase" to JsonPrimitive(store.phase.name),
            "notice" to str(store.notice),
            "spectatorCount" to JsonPrimitive(store.spectatorCount),
            "heldMySeq" to JsonPrimitive(store.heldMySeq),
            "heldOpponentSeq" to JsonPrimitive(store.heldOpponentSeq),
            "opponentAttackTotal" to JsonPrimitive(store.opponentAttackTotal),
            "opponentLastSeenAtBits" to date(store.opponentLastSeenAt),
            "activeMatchID" to str(store.activeMatchID),
            "rubyBalance" to long(store.rubyBalance),
            "serverClockOffsetBits" to bits(store.serverClockOffset),
            "duelMatchID" to str(store.duelMatchID),
            "dismissed" to JsonArray(store.dismissedMatchIDs.sorted().map(::JsonPrimitive)),
        )
        val match = store.match
        out["match"] = if (match == null) JsonNull else obj(
            "id" to JsonPrimitive(match.id),
            "stake" to JsonPrimitive(match.stake),
            "seed" to (match.seed?.let(::JsonPrimitive) ?: JsonNull),
            "opponentID" to JsonPrimitive(match.opponent.id),
            "opponentName" to JsonPrimitive(match.opponent.displayName),
            "acceptedAtBits" to date(match.acceptedAt),
            "readyDeadlineBits" to date(match.readyDeadline),
            "startAtBits" to date(match.startAt),
            "maxEndBits" to date(match.maxEnd),
            "finishedAtBits" to date(match.finishedAt),
            "meReady" to JsonPrimitive(match.meReady),
            "isFinished" to JsonPrimitive(match.isFinished),
            "outcome" to str(match.outcome?.name),
            "endReason" to str(match.endReason?.rawValue),
            "rubyDelta" to int(match.rubyDelta),
            "opponentBoard" to obj(
                "hasBoard" to JsonPrimitive(match.opponentBoard.hasBoard),
                "lines" to JsonPrimitive(match.opponentBoard.lines),
                "attackSent" to JsonPrimitive(match.opponentBoard.attackSent),
                "pending" to JsonPrimitive(match.opponentBoard.pending),
                "toppedOut" to JsonPrimitive(match.opponentBoard.toppedOut),
                "ready" to JsonPrimitive(match.opponentBoard.ready),
                "cells" to JsonPrimitive(cellsText(match.opponentBoard.cells)),
            ),
        )
        val stats = store.myStats
        out["myStats"] = if (stats == null) JsonNull else obj(
            "lines" to JsonPrimitive(stats.lines), "attackSent" to JsonPrimitive(stats.attackSent),
            "pendingGarbage" to JsonPrimitive(stats.pendingGarbage), "levelFloor" to JsonPrimitive(stats.levelFloor),
            "toppedOut" to JsonPrimitive(stats.toppedOut),
        )
        val duel = store.duel
        out["duel"] = if (duel == null) JsonNull else {
            val g = duel.game
            obj(
                "seed" to JsonPrimitive(duel.seed),
                "seq" to JsonPrimitive(duel.seq),
                "garbageApplied" to JsonPrimitive(duel.garbageApplied),
                "started" to JsonPrimitive(duel.started),
                "finished" to JsonPrimitive(duel.finished),
                "startAtBits" to (duel.startAt?.let(::bits) ?: JsonNull),
                "simulatedBits" to bits(duel.simulated),
                "droppedSecondsBits" to bits(duel.droppedSeconds),
                "lastReportAtBits" to (duel.lastReportAt?.let(::bits) ?: JsonNull),
                "reportedAttackSent" to JsonPrimitive(duel.reportedAttackSent),
                "isLive" to JsonPrimitive(duel.isLive),
                "toppedOut" to JsonPrimitive(duel.toppedOut),
                "board" to JsonPrimitive(TetrisDuelBoard.encode(g)),
                "active" to (g.active?.let { a ->
                    obj("piece" to JsonPrimitive(letters[a.piece.rawValue].toString()), "rotation" to JsonPrimitive(a.rotation.rawValue),
                        "column" to JsonPrimitive(a.column), "row" to JsonPrimitive(a.row))
                } ?: JsonNull),
                "next" to JsonPrimitive(g.next.take(5).joinToString("") { letters[it.rawValue].toString() }),
                "held" to JsonPrimitive(g.heldPiece?.let { letters[it.rawValue].toString() } ?: "-"),
                "holdUsed" to JsonPrimitive(g.holdUsed),
                "score" to JsonPrimitive(g.score),
                "lines" to JsonPrimitive(g.lines),
                "attackSentTotal" to JsonPrimitive(g.attackSentTotal),
                "pendingGarbage" to JsonArray(g.pendingGarbage.map(::JsonPrimitive)),
                "levelFloor" to JsonPrimitive(g.levelFloor),
                "phase" to gamePhase(g.phase),
                "elapsedBits" to bits(g.elapsed),
            )
        }
        return JsonObject(out)
    }

    /** 첫 불일치 경로(없으면 null) — 골든 실패 문구에 싣는다. */
    private fun firstDifference(a: JsonElement, b: JsonElement, path: String = "$"): String? = when {
        a is JsonObject && b is JsonObject -> {
            val keys = (a.keys + b.keys).sorted()
            keys.firstNotNullOfOrNull { k ->
                val x = a[k]
                val y = b[k]
                when {
                    x == null -> "$path.$k: Swift 에만 있다"
                    y == null -> "$path.$k: Kotlin 에만 있다"
                    else -> firstDifference(x, y, "$path.$k")
                }
            }
        }
        a is JsonArray && b is JsonArray ->
            if (a.size != b.size) "$path: 길이 ${a.size} ≠ ${b.size}"
            else a.indices.firstNotNullOfOrNull { firstDifference(a[it], b[it], "$path[$it]") }
        else -> if (a == b) null else "$path: Swift $a ≠ Kotlin $b"
    }

    private fun runInput(key: String, store: TetrisDuelStore) {
        when (key) {
            "left" -> { store.setLeftHeld(true); store.setLeftHeld(false) }
            "right" -> { store.setRightHeld(true); store.setRightHeld(false) }
            "moveLeftOne" -> store.moveLeftOneCell()
            "moveRightOne" -> store.moveRightOneCell()
            "softDropOne" -> store.softDropOneCell()
            "rotateCW" -> store.rotate(clockwise = true)
            "rotateCCW" -> store.rotate(clockwise = false)
            "hold" -> store.hold()
            "hardDrop" -> store.hardDrop()
            else -> fail("모르는 입력 $key")
        }
    }

    private fun TestScope.replay(caseId: String, steps: JsonArray): List<JsonObject> {
        val wall = golden.spec["wallBase"]!!.jsonPrimitive.content.let(Golden::bits)
        var now = 0.0
        val store = TetrisDuelStore(host = null, scope = backgroundScope, clock = { SwiftDate(wall) })
        store.uptime = { now }
        store.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        store.pollStepSeconds = Double.POSITIVE_INFINITY
        val results = mutableListOf<JsonObject>()
        for (element in steps) {
            val step = element as JsonObject
            val record = linkedMapOf<String, JsonElement>()
            when (val op = step.string("op")) {
                "apply" -> {
                    val at = step.bits("receivedAtBits")
                    now = at
                    val payload = json.decodeFromJsonElement(TetrisStatePayload.serializer(), step.obj("payload"))
                    record["apply"] = JsonPrimitive(store.applyState(payload, at).name)
                }
                "tick" -> {
                    now = step.bits("nowBits")
                    store.tick(now)
                }
                "input" -> {
                    now = step.bits("uptimeBits")
                    runInput(step.string("key"), store)
                }
                "close" -> store.windowDidClose()
                else -> fail(golden.failure(caseId, "모르는 단계 $op"))
            }
            record["state"] = dump(store)
            results += JsonObject(record)
        }
        store.stopGameLoop()
        return results
    }

    @Test
    fun resumePointTableMatchesSwift() {
        val rows = golden.cases.filter { it.string("id").startsWith("resume-") }
        assertEquals(13, rows.size, "resumePoint 표 13건")
        for (case in rows) {
            val id = case.string("id")
            val me = case["me"]?.takeIf { it !is JsonNull }?.let { json.decodeFromJsonElement(TetrisPlayerRow.serializer(), it) }
            val start = case["startAtMs"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long?.toDouble()
            val point = TetrisDuelStore.resumePoint(me, start)
            val actual: JsonElement = point?.let { p ->
                obj("seq" to JsonPrimitive(p.seq), "board" to JsonPrimitive(p.board), "lines" to JsonPrimitive(p.lines),
                    "garbageSent" to JsonPrimitive(p.garbageSent), "garbageApplied" to JsonPrimitive(p.garbageApplied),
                    "pending" to JsonPrimitive(p.pending), "elapsedBits" to bits(p.elapsedSeconds))
            } ?: JsonNull
            val diff = firstDifference(case["point"]!!, actual)
            assertEquals(null, diff, golden.failure(id, diff ?: ""))
        }
    }

    @Test
    fun storeFlowsMatchSwift() = runTest {
        val flows = golden.cases.filter { it.string("id").startsWith("flow-") }
        assertEquals(listOf("flow-resume", "flow-countdown", "flow-resume-rejected"), flows.map { it.string("id") }, "흐름 목록 잠금")
        for (case in flows) {
            val id = case.string("id")
            val expected = case.array("results")
            val actual = replay(id, case.array("steps"))
            assertEquals(expected.size, actual.size, golden.failure(id, "단계 수"))
            for ((index, pair) in expected.zip(actual).withIndex()) {
                val diff = firstDifference(pair.first, pair.second, "results[$index]")
                assertEquals(null, diff, golden.failure(id, diff ?: ""))
            }
        }
    }

    /**
     * 유지 가드 둘(검증 지적 V02·V03 — `startAt ?: base.startAt` · `meReady || base.meReady`): 시작 시각을 받은 뒤 온 늦은 응답의 빈칸
     * (start_at_ms 없음 · me.ready=false)이 앞 값을 지우지 못한다. 골든 flow-countdown 에 그 단계가 있어야 하고(생성기가 빠뜨리면 빨강),
     * Kotlin 재생이 시작 시각·준비를 그대로 든다. 기준선(다른 입력): 같은 단계에 새 start_at_ms 를 실으면 시작 시각이 그 값으로 바뀐다.
     */
    @Test
    fun lateBlankFieldsDoNotEraseStartAtOrReady() = runTest {
        val case = golden.cases.first { it.string("id") == "flow-countdown" }
        val steps = case.array("steps").map { it as JsonObject }
        fun JsonObject.isApply() = string("op") == "apply"
        val withStart = steps.indexOfFirst { it.isApply() && it.obj("payload")["start_at_ms"] != null }
        val late = steps.indices.firstOrNull { i ->
            val step = steps[i]
            i > withStart && step.isApply() && step.obj("payload").let { p ->
                p["start_at_ms"] == null && p.string("status") == "active" && p.obj("me")["ready"] == JsonPrimitive(false)
            }
        }
        assertTrue(withStart >= 0 && late != null, "flow-countdown 에 '시작 시각 뒤 빈칸 응답' 단계가 없다 — 유지 가드 둘을 아무도 안 잰다")
        val actual = replay("flow-countdown(유지)", JsonArray(steps.take(late + 1)))
        fun match(i: Int) = actual[i].obj("state").obj("match")
        assertEquals(JsonPrimitive("applied"), actual[late]["apply"], "seq 가드가 가린 단계면 유지 가드를 못 잰다")
        assertTrue(match(withStart)["startAtBits"] !is JsonNull, "전제: 시작 시각을 받았다")
        assertEquals(match(withStart)["startAtBits"], match(late)["startAtBits"], "늦은 응답의 null 이 시작 시각을 지웠다")
        assertEquals(JsonPrimitive(false), match(0)["meReady"], "기준선: 준비 전에는 false 다")
        assertEquals(JsonPrimitive(true), match(late)["meReady"], "늦은 응답의 ready=false 가 준비를 되돌렸다")

        val payload = steps[late].obj("payload")
        val moved = payload["server_now_ms"]!!.jsonPrimitive.long + 9_000
        val altered = JsonObject(steps[late] + ("payload" to JsonObject(payload + ("start_at_ms" to JsonPrimitive(moved)))))
        val baseline = replay("flow-countdown(기준선)", JsonArray(steps.take(late) + altered))
        assertTrue(baseline[late].obj("state").obj("match")["startAtBits"] != match(withStart)["startAtBits"],
            "기준선: 새 start_at_ms 를 실은 응답은 시작 시각을 바꿔야 한다(칸이 살아 있다)")
    }

    /** 대조(기준선이 다른 입력): 재개 흐름의 첫 apply 에서 내 행의 last_seen 을 시작 시각으로 바꾸면 새 판이 서고 덤프가 갈린다. */
    @Test
    fun theFirstApplyReallyResumesFromTheServerRow() = runTest {
        val case = golden.cases.first { it.string("id") == "flow-resume" }
        val steps = case.array("steps")
        val first = steps[0] as JsonObject
        val payload = first.obj("payload")
        val me = payload.obj("me")
        val start = payload["start_at_ms"]!!
        val altered = JsonObject(first + ("payload" to JsonObject(payload + ("me" to JsonObject(me + ("last_seen_ms" to start))))))
        val actual = replay("flow-resume(대조)", JsonArray(listOf(altered)))
        val expected = case.array("results")[0]
        assertTrue(firstDifference(expected, actual[0]) != null, "새 판(재개 아님)이면 덤프가 갈라야 한다")
        val duel = actual[0].obj("state").obj("duel")
        assertEquals(JsonPrimitive(false), duel["started"], "판 시작 전 보고만 있으면 새 판이다")
        assertEquals(GoldenCanonical.text(JsonPrimitive(4)), GoldenCanonical.text(duel["garbageApplied"]!!), "받아들인 누계는 서버 값에서 잇는다")
    }
}
