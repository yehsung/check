// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportTetris.swift(tetris/rules · bags · garbage-holes · scripted 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.DualFold
import com.yehsung.aingcheck.core.rules.minigame.Fnv1a64
import com.yehsung.aingcheck.core.rules.minigame.GoldenFailures
import com.yehsung.aingcheck.core.rules.minigame.GoldenOps
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRandom
import com.yehsung.aingcheck.core.rules.minigame.ReplayTrace
import com.yehsung.aingcheck.core.rules.tetris.TetrisGoldenSupport.LETTERS
import com.yehsung.aingcheck.core.rules.tetris.TetrisGoldenSupport.bitsEqual
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Kotlin 테트리스 엔진이 Swift 와 비트로 같다(C§5.1 E2·E3, G §2-3 W1-a ①③). 골든 다섯: 규칙표 · 7-bag · 방해 줄 구멍 · 대본 A~G ·
 * 손으로 짠 판(T-스핀 정식·미니·마지막 킥 · B2B · 퍼펙트 클리어).
 * 대본은 조종사 없이 연산만 재생해 64프레임 체크포인트 · 프레임 바이트 · 끝 상태를 대조한다 — 갈리면 처음 갈린 **프레임 번호**를 말한다(②).
 * 모든 골든은 case 목록을 잠근다 — 빠진 case 는 대조 없이 사라지므로(검증 지적) 늘거나 줄면 빨강이다.
 */
class TetrisGoldenTest {

    @Test
    fun rulesTableMatchesSwift() {
        val golden = Golden.load("tetris/rules")
        val f = GoldenFailures(golden)
        val spins = listOf("none" to TetrisGame.Spin.none, "mini" to TetrisGame.Spin.mini, "full" to TetrisGame.Spin.full)
        fun ints(case: JsonObject, key: String = "values") = GoldenOps.ints(case.string(key))
        fun bits(case: JsonObject, key: String = "valuesBits") = GoldenOps.bits(case.string(key))
        fun table(id: String, want: List<Int>, from: Int, fn: (Int) -> Int) = want.forEachIndexed { i, w ->
            val got = fn(from + i)
            f.check(id, got == w) { "입력 ${from + i}: 기대 $w · Kotlin $got" }
        }
        fun bitsTable(id: String, want: List<Double>, from: Int, fn: (Int) -> Double) = want.forEachIndexed { i, w ->
            val got = fn(from + i)
            f.check(id, got.toRawBits() == w.toRawBits()) { "입력 ${from + i}: 기대 ${Golden.bitsText(w)} · Kotlin ${Golden.bitsText(got)}" }
        }
        for (case in golden.cases) {
            val id = case.string("id")
            when {
                id == "level" -> table(id, ints(case), case.int("from")) { TetrisGame.level(forAdvance = it) }
                id == "scoreLevel" -> table(id, ints(case), case.int("from")) { TetrisGame.scoreLevel(forLevel = it) }
                id == "gravityStage" -> table(id, ints(case), case.int("from")) { TetrisGame.gravityStage(forLevel = it) }
                id == "gravitySecondsForStage" -> bitsTable(id, bits(case), case.int("from")) { TetrisGame.gravitySeconds(forStage = it) }
                id == "gravitySecondsForLevel" -> bitsTable(id, bits(case), case.int("from")) { TetrisGame.gravitySecondsForLevel(it) }
                id == "softDropSeconds" -> bitsTable(id, bits(case), case.int("from")) { TetrisGame.softDropSeconds(forLevel = it) }
                id == "lockDelaySeconds" -> bitsTable(id, bits(case), case.int("from")) { TetrisGame.lockDelaySeconds(forLevel = it) }
                id == "lockResetLimit" -> table(id, ints(case), case.int("from")) { TetrisGame.lockResetLimit(forLevel = it) }
                id == "lockResetRefreshes" -> GoldenOps.bools(case.string("values")).forEachIndexed { i, w ->
                    val got = TetrisGame.lockResetRefreshes(forLevel = case.int("from") + i)
                    f.check(id, got == w) { "레벨 ${case.int("from") + i}: 기대 $w · Kotlin $got" }
                }
                id == "attackLines" -> table(id, ints(case), case.int("from")) { TetrisGame.attackLines(it) }
                id.startsWith("actionPoints-") -> {
                    val spin = spins.first { it.first == id.removePrefix("actionPoints-") }.second
                    table(id, ints(case), case.int("from")) { TetrisGame.actionPoints(it, spin) }
                }
                id.startsWith("isDifficult-") -> {
                    val spin = spins.first { it.first == id.removePrefix("isDifficult-") }.second
                    GoldenOps.bools(case.string("values")).forEachIndexed { i, w ->
                        val got = TetrisGame.isDifficult(case.int("from") + i, spin)
                        f.check(id, got == w) { "줄 ${case.int("from") + i}: 기대 $w · Kotlin $got" }
                    }
                }
                id == "perfectClearPoints" -> {
                    table(id, ints(case, "plain"), case.int("from")) { TetrisGame.perfectClearPoints(it, backToBackTetris = false) }
                    table(id, ints(case, "b2bTetris"), case.int("from")) { TetrisGame.perfectClearPoints(it, backToBackTetris = true) }
                }
                id == "comboPoints" -> {
                    val got = ArrayList<Int>()
                    for (c in -2..6) for (s in listOf(1, 2, 3, 30)) got += TetrisGame.comboPoints(c, s)
                    f.check(id, got == ints(case)) { "Kotlin $got" }
                }
                id == "placementPoints" -> {
                    val got = ArrayList<Int>()
                    for (lines in 0..4) for ((_, spin) in spins) for (level in listOf(1, 7, 30)) for (b2b in listOf(false, true))
                        for (combo in listOf(-1, 0, 3)) for (perfect in listOf(false, true))
                            got += TetrisGame.placementPoints(lines, spin, level, b2b, combo, perfect)
                    val want = ints(case)
                    val first = got.indices.firstOrNull { it >= want.size || got[it] != want[it] }
                    f.check(id, got.size == want.size && first == null) { "첫 불일치 순번 $first: 기대 ${first?.let { want.getOrNull(it) }} · Kotlin ${first?.let { got[it] }}" }
                }
                id == "shapes" -> {
                    val t = case.obj("table")
                    for (piece in TetrisGame.Piece.entries) for (rotation in TetrisGame.Rotation.entries) {
                        val key = "${LETTERS[piece.rawValue]}${rotation.rawValue}"
                        val got = TetrisGame.shape(piece, rotation).joinToString(" ") { "${it.dx},${it.dy}" }
                        f.check(id, got == t.string(key)) { "$key: 기대 ${t.string(key)} · Kotlin $got" }
                    }
                }
                id == "kicks" -> {
                    val t = case.obj("table")
                    for (piece in TetrisGame.Piece.entries) for (from in TetrisGame.Rotation.entries) for (to in TetrisGame.Rotation.entries) {
                        val key = "${LETTERS[piece.rawValue]}${from.rawValue}${to.rawValue}"
                        val got = TetrisGame.kicks(piece, from, to).joinToString(" ") { "${it.dx},${it.dy}" }
                        f.check(id, got == t.string(key)) { "$key: 기대 ${t.string(key)} · Kotlin $got" }
                    }
                }
                id == "advanceToNextLevel" -> table(id, ints(case), case.int("from")) {
                    TetrisGame(0uL, TetrisGame.emptyBoard(), active = null, advance = it).advanceToNextLevel
                }
                id == "constants" -> {
                    val want = mapOf(
                        "columns" to TetrisGame.columns, "totalRows" to TetrisGame.totalRows, "visibleRows" to TetrisGame.visibleRows,
                        "firstVisibleRow" to TetrisGame.firstVisibleRow, "spawnRow" to TetrisGame.spawnRow,
                        "spawnColumn" to TetrisGame.spawnColumn, "nextCount" to TetrisGame.nextCount,
                        "advanceAtGravityCap" to TetrisGame.advanceAtGravityCap, "scoreLevelCap" to TetrisGame.scoreLevelCap,
                        "maxScore" to TetrisGame.maxScore, "kindMaxScore" to MiniGameKind.tetris.maxScore,
                        "maxGarbageInsertPerLock" to TetrisGame.maxGarbageInsertPerLock, "maxLevelFloor" to TetrisGame.maxLevelFloor,
                    )
                    for ((key, value) in want) f.check(id, case.int(key) == value) { "$key: 기대 ${case.int(key)} · Kotlin $value" }
                    val doubles = mapOf(
                        "maxStepBits" to TetrisGame.maxStep, "dasSecondsBits" to TetrisGame.dasSeconds, "arrSecondsBits" to TetrisGame.arrSeconds,
                        "areSecondsBits" to TetrisGame.areSeconds, "lineClearSecondsBits" to TetrisGame.lineClearSeconds,
                        "overHoldBits" to TetrisGame.overHold, "maxGroundedSecondsBits" to TetrisGame.maxGroundedSeconds,
                    )
                    for ((key, value) in doubles) f.check(id, bitsEqual(value, case.string(key))) { "$key: 기대 ${case.string(key)} · Kotlin ${Golden.bitsText(value)}" }
                    val order = TetrisGoldenSupport.pieces(TetrisGame.Piece.entries)
                    f.check(id, order == case.string("pieceOrder")) { "조각 순서(7-bag 입력): Kotlin $order" }
                }
                id == "layout" -> {
                    val l = TetrisLayout
                    val constants = listOf(
                        l.logicalSize.width, l.logicalSize.height, l.cell, l.outerMargin, l.columnWidth, l.gutter, l.boardX, l.boardWidth,
                        l.rightColumnX, l.bufferY, l.boardTopY, l.boardBottomY, l.bandY, l.bandHeight, l.textMinX, l.textMaxX, l.labelY,
                        l.labelHeight, l.boxY, l.boxHeight, l.stageChipY, l.stageChipHeight, l.levelCaptionY, l.levelValueY,
                        l.linesCaptionY, l.linesValueY, l.captionHeight, l.valueHeight, l.slotGap, l.miniCell,
                    )
                    fun same(got: List<Double>, key: String) = got.map { it.toRawBits() } == GoldenOps.bits(case.string(key)).map { it.toRawBits() }
                    f.check(id, same(constants, "constantsBits")) { "배치 상수 Kotlin $constants" }
                    f.check(id, same((0 until 5).map { l.slotY(it) }, "slotYBits")) { "slotY" }
                    val rects = listOf(l.cellRect(20, 0), l.cellRect(39, 9), l.cellRect(19, 4), l.wellRect)
                    f.check(id, same(rects.flatMap { listOf(it.x, it.y, it.width, it.height) }, "rectsBits")) { "사각형 Kotlin $rects" }
                    val p = TetrisPalette
                    val palette = mutableListOf(p.wellInk.r, p.wellInk.g, p.wellInk.b, p.wellOpacity, p.ghostOpacity, p.spentOpacity)
                    for (piece in TetrisGame.Piece.entries) p.rgb.getValue(piece).let { palette += listOf(it.r, it.g, it.b) }
                    f.check(id, same(palette, "paletteBits")) { "팔레트 Kotlin $palette" }
                }
                else -> f.fail(id, "Kotlin 시험이 모르는 case — 골든이 늘었으면 시험을 같이 넓힌다")
            }
        }
        f.assertNone()
        assertEquals(RULES_IDS, golden.cases.map { it.string("id") }, "tetris/rules case 목록이 바뀌었다 — 빠진 표는 Kotlin 이 모른다")
        assertTrue(f.compared > 2_500, "규칙표를 덜 읽었다(${f.compared})")
    }

    /** 중력 비트 표 상수(엔진이 든 값)가 골든과 비트로 같다 — pow 를 부르지 않는 대신 이 표가 계약이다(G §8-14). */
    @Test
    fun gravityConstantTableIsTheSwiftBits() {
        val golden = Golden.load("tetris/rules")
        val case = golden.case("gravitySecondsForStage")
        val want = GoldenOps.bits(case.string("valuesBits"))
        val from = case.int("from")
        for (stage in 1..20) {
            val w = want[stage - from]
            assertEquals(w.toRawBits(), TetrisGame.GRAVITY_SECONDS_BITS[stage - 1], golden.failure("gravitySecondsForStage", "단계 $stage 상수 표"))
        }
    }

    @Test
    fun bagStreamsMatchSwift() {
        val golden = Golden.load("tetris/bags")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            val seed = case.hex64("seed")
            val rng = MiniGameRandom(seed)
            val pieces = ArrayList<TetrisGame.Piece>()
            repeat(10) { pieces += TetrisGame.shuffledBag(rng) }
            val got = TetrisGoldenSupport.pieces(pieces)
            val want = case.string("pieces")
            f.check(id, got == want) { "첫 불일치 순번 ${got.indices.firstOrNull { got[it] != want.getOrNull(it) }}: 기대 $want · Kotlin $got" }
            val game = TetrisGame(seed)
            game.action()
            val active = game.active?.let { LETTERS[it.piece.rawValue].toString() } ?: "-"
            f.check(id, active == case.string("firstActive")) { "첫 조각 Kotlin $active" }
            f.check(id, TetrisGoldenSupport.pieces(game.next) == case.string("firstNext")) { "첫 넥스트 Kotlin ${TetrisGoldenSupport.pieces(game.next)}" }
        }
        f.assertNone()
        assertEquals(BAG_IDS, golden.cases.map { it.string("id") }, "tetris/bags case 목록이 바뀌었다")
        assertTrue(golden.cases.any { it.hex64("seed") >= 0x8000000000000000uL }, "위 비트가 선 시드가 없다(부호 없는 나머지를 못 잰다)")
    }

    @Test
    fun garbageHolesMatchSwift() {
        val golden = Golden.load("tetris/garbage-holes")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            val seed = case.hex64("seed")
            val game = TetrisGame(
                seed, TetrisGame.emptyBoard(),
                active = TetrisGame.ActivePiece(TetrisGame.Piece.o, column = TetrisGame.spawnColumn, row = TetrisGame.spawnRow),
                pendingGarbage = List(8) { 1 },
            )
            val holes = ArrayList<Int>()
            var locks = 0
            for (k in 1..4) {
                if (k > 1) {
                    game.step(0.05)
                    game.step(0.05)
                    repeat(8) { game.receiveGarbage(1) }
                }
                game.action()
                locks += 1
                if (game.phase is TetrisGame.Phase.Over) break
                for (row in 32 until 40) {
                    val mask = game.garbageMask[row]
                    val hole = (0 until TetrisGame.columns).firstOrNull { (mask and (1 shl it)) == 0 } ?: continue
                    holes += hole
                }
            }
            val want = GoldenOps.ints(case.string("holes"))
            f.check(id, holes == want) { "구멍 기대 $want · Kotlin $holes" }
            f.check(id, locks == case.int("locks")) { "굳힘 수 Kotlin $locks" }
            f.check(id, TetrisGoldenSupport.phaseMatches(game.phase, case.obj("phase"))) { "단계 Kotlin ${game.phase}" }
            f.check(id, TetrisGoldenSupport.boardText(game) == case.string("board")) { "판 Kotlin ${TetrisGoldenSupport.boardText(game)}" }
        }
        f.assertNone()
        assertEquals(BAG_IDS.take(64), golden.cases.map { it.string("id") }, "tetris/garbage-holes case 목록이 바뀌었다")
    }

    @Test
    fun scriptedReplaysMatchSwift() {
        val golden = Golden.load("tetris/scripted")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            val run = replay(case)
            val final = case.obj("final")
            val mismatch = run.trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), run.fold.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            val fields = TetrisGoldenSupport.finalMismatches(run.game, final)
            f.check(id, fields.isEmpty()) { "끝 상태 칸 $fields" }
            // 파생 값(ghost · isPlaying · isGameOver · difficultyLevel · pendingGarbageLines) — 규칙 해시(V0360 고정) 밖의 따로 접은 해시.
            val derived = case.obj("derived")
            val wantDerived = GoldenOps.hexes(derived.string("checkpoints"))
            val firstDerived = run.derivedCheckpoints.indices.firstOrNull { it >= wantDerived.size || run.derivedCheckpoints[it] != wantDerived[it] }
            f.check(id, firstDerived == null && run.derivedCheckpoints.size == wantDerived.size && run.derived.value == derived.hex64("hash")) {
                "파생 값(ghost·isPlaying·isGameOver·difficultyLevel·pendingGarbageLines)이 갈렸다 — 처음 갈린 체크포인트 구간 " +
                    "${firstDerived?.let { "[${it * run.trace.checkpointEvery}, ${(it + 1) * run.trace.checkpointEvery}]" } ?: "없음(끝 해시)"}"
            }
        }
        f.assertNone()
        assertEquals(listOf("A", "B", "C", "D", "E", "F", "G"), golden.cases.map { it.string("id") })
    }

    /**
     * 손으로 짠 판(tetris/fixtures): 대본 A~G 가 한 번도 지나지 않는 E3 갈래 — T-스핀 정식(앞 모서리 둘) · 미니 · 킥 미니 ·
     * 마지막(5번째) 킥 정식 · 반시계 마지막 킥 · TST · B2B(T-스핀 · 미니 · 테트리스) · 퍼펙트(B2B 테트리스 3200 포함).
     */
    @Test
    fun fixtureReplaysMatchSwift() {
        val golden = Golden.load("tetris/fixtures")
        val f = GoldenFailures(golden)
        val seen = HashSet<String>()
        for (case in golden.cases) {
            val id = case.string("id")
            val run = replayFixture(case)
            val final = case.obj("final")
            val mismatch = run.trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), run.fold.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            val events = run.events.joinToString(" ")
            f.check(id, events == case.string("events")) { "굳힘 사건(줄:스핀:B2B:퍼펙트:점수:공격) 기대 ${case.string("events")} · Kotlin $events" }
            val fields = TetrisGoldenSupport.finalMismatches(run.game, final)
            f.check(id, fields.isEmpty()) { "끝 상태 칸 $fields" }
            for (e in case.string("events").split(' ').filter { it.isNotEmpty() }) {
                val (lines, spin, b2b, perfect) = e.split(':')
                if (spin != "none") seen += "$spin-${if (lines == "0") "zero" else "lines"}"
                if (b2b == "1") seen += "b2b-$spin"
                if (perfect == "1") seen += if (b2b == "1") "pc-b2b" else "pc"
                if (lines == "4") seen += "tetris"
            }
        }
        f.assertNone()
        assertEquals(FIXTURE_IDS, golden.cases.map { it.string("id") }, "tetris/fixtures case 목록이 바뀌었다")
        // 골든이 다시 만들어져도 E3 갈래가 빠지지 않게(Swift 생성기의 #expect 와 같은 목록).
        val required = setOf("full-lines", "mini-lines", "mini-zero", "b2b-full", "b2b-mini", "b2b-none", "pc", "pc-b2b", "tetris")
        assertTrue(seen.containsAll(required), "손으로 짠 판 골든이 판정 갈래를 다 지나지 않는다: 빠짐 ${required - seen}")
    }

    class Run(val game: TetrisGame, val fold: DualFold, val trace: ReplayTrace, val derived: Fnv1a64, val derivedCheckpoints: List<ULong>)

    class FixtureRun(val game: TetrisGame, val fold: DualFold, val trace: ReplayTrace, val events: List<String>)

    companion object {
        /** contract/README.md §2-4: 시작 판 → 판 전체 접기 → 프레임마다 [연산 → step(dt) → light, advance 가 바뀌면 board] · 결과면 멈춤. */
        fun replay(case: JsonObject): Run {
            val seed = case.hex64("seed")
            val dt = Golden.bits(case.string("dtBits"))
            val start = case.obj("start")
            val game = when (start.string("kind")) {
                "new" -> TetrisGame(seed).also { g ->
                    start.string("preOps").split(' ').filter { it.isNotEmpty() }.forEach { TetrisGoldenSupport.applyBaseOp(it, g) }
                }
                "advance" -> TetrisGame(
                    seed, TetrisGame.emptyBoard(), active = null,
                    phase = TetrisGame.Phase.Are(TetrisGame.areSeconds), advance = start.int("advance"),
                )
                else -> error("모르는 시작 ${start.string("kind")}")
            }
            val fold = DualFold()
            TetrisGoldenSupport.board(game, fold)
            val derived = Fnv1a64()
            fun foldDerived() { for (v in TetrisGoldenSupport.derivedValues(game)) derived.add(v) }
            foldDerived()
            val derivedCheckpoints = ArrayList<ULong>()
            val trace = ReplayTrace(case.int("checkpointEvery"))
            for (ops in GoldenOps.decode(case.string("ops"))) {
                fold.beginFrame()
                val before = game.advance
                for (op in ops) TetrisGoldenSupport.applyBaseOp(op, game)
                game.step(dt)
                TetrisGoldenSupport.light(game, fold)
                if (game.advance != before) TetrisGoldenSupport.board(game, fold)
                foldDerived()
                trace.endFrame(fold)
                if (trace.frames % trace.checkpointEvery == 0) derivedCheckpoints += derived.value
                if (game.phase == TetrisGame.Phase.Result) break
            }
            return Run(game, fold, trace, derived, derivedCheckpoints)
        }

        private fun piece(letter: Char): TetrisGame.Piece = TetrisGame.Piece.entries[LETTERS.indexOf(letter).also { require(it >= 0) { "모르는 조각 글자 $letter" } }]

        /** tetris/fixtures 재생(Swift `fixtureReplay`): 시작 판 → [board · light · derived] → 프레임마다 [연산 → step → light · derived, advance 가 바뀌면 board · 사건]. */
        fun replayFixture(case: JsonObject): FixtureRun {
            val start = case.obj("start")
            require(start.string("kind") == "fixture") { "모르는 시작 ${start.string("kind")}" }
            val a = start.obj("active")
            val game = TetrisGame(
                case.hex64("seed"),
                TetrisGame.boardFixture(start.array("rows").map { it.stringValue() }),
                active = TetrisGame.ActivePiece(
                    piece(a.string("piece").single()), TetrisGame.Rotation.entries.first { it.rawValue == a.int("rotation") },
                    column = a.int("column"), row = a.int("row"),
                ),
                next = start.string("next").map { piece(it) },
                combo = start.int("combo"),
                backToBack = start.int("backToBack"),
            )
            val dt = Golden.bits(case.string("dtBits"))
            val fold = DualFold()
            TetrisGoldenSupport.board(game, fold)
            TetrisGoldenSupport.light(game, fold)
            TetrisGoldenSupport.derived(game, fold)
            val trace = ReplayTrace(case.int("checkpointEvery"))
            val events = ArrayList<String>()
            for (ops in GoldenOps.decode(case.string("ops"))) {
                fold.beginFrame()
                val before = game.advance
                for (op in ops) TetrisGoldenSupport.applyBaseOp(op, game)
                game.step(dt)
                TetrisGoldenSupport.light(game, fold)
                TetrisGoldenSupport.derived(game, fold)
                if (game.advance != before) {
                    TetrisGoldenSupport.board(game, fold)
                    events += TetrisGoldenSupport.event(game.lastClear)
                }
                trace.endFrame(fold)
                if (game.phase == TetrisGame.Phase.Result) break
            }
            return FixtureRun(game, fold, trace, events)
        }

        val RULES_IDS: List<String> = listOf(
            "level", "scoreLevel", "gravityStage", "gravitySecondsForStage", "gravitySecondsForLevel", "softDropSeconds",
            "lockDelaySeconds", "lockResetLimit", "lockResetRefreshes", "attackLines",
            "actionPoints-none", "isDifficult-none", "actionPoints-mini", "isDifficult-mini", "actionPoints-full", "isDifficult-full",
            "perfectClearPoints", "comboPoints", "placementPoints", "shapes", "kicks", "advanceToNextLevel", "constants", "layout",
        )

        val BAG_IDS: List<String> = listOf(
            "zero", "one", "server-max", "int63-max", "int63-min", "uint64-max", "tetris-a", "tetris-b", "tetris-c", "tetris-d",
        ) + (0 until 190).map { "s$it" }

        val FIXTURE_IDS: List<String> = listOf(
            "tsd", "tsd-b2b", "no-rotation", "mini", "mini-kick", "mini-zero", "final-kick", "final-kick-ccw", "tst", "b2b-tetris-pc", "pc-double",
        )
    }
}
