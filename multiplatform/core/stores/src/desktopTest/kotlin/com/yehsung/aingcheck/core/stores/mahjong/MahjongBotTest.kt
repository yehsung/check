// 원본: Tests/checkTests/MahjongBotTests.swift @ e4995a3a — Android 판 8
// 연습 봇: ① 엔진 자체 대국에서 결정 ⊂ myDecision ② 봇 샹텐 셈 = 규칙 샹텐 ③ 결정 단위 규칙(손 픽스처 + 기준선) ④ 느린 시계.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom
import com.yehsung.aingcheck.core.rules.ai.SwiftRandomSource
import com.yehsung.aingcheck.core.rules.ai.nextIndex
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongHand
import com.yehsung.aingcheck.core.rules.mahjong.MahjongMeldType
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTiles
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.test.fail

internal object MahjongBotPlay {
    const val EPOCH_MS = 1_800_000_000_000.0

    /** Swift `Array.shuffle(using:)` — 앞에서부터 남은 칸 수 안의 난수와 맞바꾼다. */
    fun wall(rng: SwiftRandomSource): List<Int> {
        val w = (0 until 136).toMutableList()
        var amount = w.size
        var i = 0
        while (amount > 1) {
            val r = rng.nextIndex(amount)
            amount -= 1
            val j = i + r
            val t = w[i]; w[i] = w[j]; w[j] = t
            i += 1
        }
        return w
    }

    fun isLegal(move: MahjongBotMove, decision: MahjongDecision?): Boolean = when {
        move == MahjongBotMove.None && decision == null -> true
        move is MahjongBotMove.Act && decision is MahjongDecision.Turn -> when (val a = move.action) {
            is MahjongTurnAction.Discard -> a.tile in decision.discard
            is MahjongTurnAction.Riichi -> a.tile in decision.riichi
            MahjongTurnAction.Tsumo -> decision.tsumo
            is MahjongTurnAction.Ankan -> a.tilesOut.sorted() in decision.ankan
            is MahjongTurnAction.Kakan -> a.tile in decision.kakan
            MahjongTurnAction.Kyuushu -> decision.kyuushu
        }
        move is MahjongBotMove.Call && decision is MahjongDecision.Call -> move.windowId == decision.windowId && when (val a = move.answer) {
            MahjongCallAnswer.Pass -> true
            MahjongCallAnswer.Ron -> decision.ron
            is MahjongCallAnswer.Pon -> a.tilesOut.sorted() in decision.pon
            is MahjongCallAnswer.Minkan -> a.tilesOut.sorted() in decision.minkan
            is MahjongCallAnswer.Chi -> a.tilesOut.sorted() in decision.chi
        }
        else -> false
    }

    fun step(move: MahjongBotMove, seat: Int): MahjongEngineStep = when (move) {
        is MahjongBotMove.Act -> MahjongEngineStep.Act(seat, move.action)
        is MahjongBotMove.Call -> MahjongEngineStep.Call(seat, move.answer)
        MahjongBotMove.None -> MahjongEngineStep.Wait
    }

    class Tally {
        var decisions = 0
        var claim = 0
        var riichi = 0
        var kuikae = 0
        var hands = 0
        val illegal = mutableListOf<String>()
    }

    /** 한 판을 끝까지(또는 국 상한까지) 봇 넷으로 둔다. 2단 보기는 결정 10번에 한 번만(나머지는 마감 지난 시계). */
    fun play(engine: MahjongTableEngine, seed: ULong, policy: MahjongBotPolicy = MahjongBotPolicy.standard, maxHands: Int = 8, maxSteps: Int = 40_000): Tally {
        val wallRng = SeededSwiftRandom(seed)
        val botRng = SeededSwiftRandom(seed xor 0x9E37_79B9_7F4A_7C15uL)
        val tally = Tally()
        if (engine.phase == MahjongEnginePhase.Idle) engine.deal(wall(wallRng))
        var steps = 0
        while (!engine.isFinished && steps < maxSteps && tally.hands < maxHands) {
            steps += 1
            val seat = engine.pendingSeats.firstOrNull()
            if (seat == null) {
                if (engine.phase is MahjongEnginePhase.HandEnd) {
                    tally.hands += 1
                    engine.startNextHand(wall(wallRng))
                } else {
                    engine.step(MahjongEngineStep.Wait)
                }
                continue
            }
            val view = engine.payload(seat, 0, EPOCH_MS)
            val full = tally.decisions % 10 == 0
            val move = MahjongBot.decide(view, botRng, pastDeadline = { !full }, policy = policy)
            tally.decisions += 1
            when (val d = view.myDecision) {
                is MahjongDecision.Call -> tally.claim += 1
                is MahjongDecision.Turn -> {
                    if (view.mySeatRow?.riichi == true) tally.riichi += 1
                    if (view.myDrawn == null) tally.kuikae += 1
                }
                null -> Unit
            }
            if (!isLegal(move, view.myDecision)) tally.illegal += "씨앗 $seed 걸음 $steps 자리 $seat: $move"
            val r = engine.step(step(move, seat))
            if (r is MahjongStepResult.Failure) {
                tally.illegal += "씨앗 $seed 걸음 $steps 자리 $seat: 엔진 거절 ${r.error} $move"
                engine.step(MahjongEngineStep.Timeout(seat))
            }
        }
        if (engine.isFinished) tally.hands += 1
        return tally
    }

    fun engine(n: Int): MahjongTableEngine {
        val scores = listOf(
            listOf(25000, 25000, 25000, 25000), listOf(32000, 18000, 26000, 24000), listOf(8000, 41000, 30000, 21000), listOf(12000, 12000, 38000, 38000),
        )
        return MahjongTableEngine(
            if (n % 3 == 0) MahjongFormat.hanchan else MahjongFormat.tonpuu, listOf(null, null, null, null), scores[n % 4],
            round = (n / 4) % 2, handNo = n % 4, honba = n % 3, kyotaku = 0,
        )
    }
}

/** 손 픽스처 — 토큰으로 패를 받고 같은 종류는 아직 안 쓴 id 를 고른다(적5 `0` 은 c 0, 보통 5 는 c 3 · 2 · 1). */
internal class MahjongBotFixture {
    val used = mutableSetOf<Int>()

    fun take(text: String): List<MahjongTile> {
        val parsed = MahjongTiles.parse(text) ?: error("토큰 $text")
        return parsed.map { t ->
            val k = t.kind
            val order = if (t.isRed) listOf(0) else if (k in listOf(4, 13, 22)) listOf(3, 2, 1) else listOf(3, 2, 1, 0)
            val c = order.firstOrNull { (k * 4 + it) !in used } ?: error("종류 $k 를 다 썼다")
            used += k * 4 + c
            MahjongTile.of(k * 4 + c)!!
        }
    }

    fun seat(no: Int, discards: String = "", melds: List<Pair<MahjongMeldType, String>> = emptyList(), riichi: Boolean = false, dealer: Int = 0): MahjongStateSeat =
        MahjongStateSeat(
            seatNo = no, wind = listOf("E", "S", "W", "N")[(no - dealer + 4) % 4], isDealer = no == dealer, score = 25000,
            discards = if (discards.isEmpty()) emptyList() else take(discards).map { MahjongDiscard(it, false, false, false) },
            melds = melds.map { (type, text) ->
                val ts = take(text)
                MahjongWireMeld(type.rawValue, ts, if (type == MahjongMeldType.ankan) null else ts.last(), if (type == MahjongMeldType.ankan) null else (no + 3) % 4)
            },
            riichi = riichi, handCount = 13 - 3 * melds.size, away = false,
        )

    companion object {
        fun view(hand: List<MahjongTile>, drawn: MahjongTile?, decision: MahjongDecision?, seats: List<MahjongStateSeat>, dora: List<MahjongTile>, wall: Int = 40, me: Int = 0) =
            MahjongStatePayload(
                match = MahjongStateMatch(
                    id = "ai-fixture", status = "active", format = "tonpuu", phase = if (decision is MahjongDecision.Turn) "turn" else "wait",
                    round = 0, handNo = 0, dealerSeat = 0, honba = 0, kyotaku = 0, wallRemaining = wall, doraIndicators = dora,
                ),
                members = emptyList(), seats = seats.sortedBy { it.seatNo }, mySeat = me, myHand = hand.sorted(), myDrawn = drawn,
                myDecision = decision, events = emptyList(),
            )

        fun turn(hand: List<MahjongTile>, drawn: MahjongTile, tsumo: Boolean = false, riichiOK: Boolean = true): MahjongDecision {
            val c14 = (hand + drawn).sorted()
            val kinds = if (riichiOK) MahjongRules.riichiDiscards(c14, 0, 25000, 40, menzen = true, already = false).toSet() else emptySet()
            return MahjongDecision.Turn(
                seq = 1, decisionSeq = 1, startedMs = 0.0, deadlineMs = 0.0, bankMs = 0, discard = c14,
                riichi = c14.filter { it.kind in kinds }, tsumo = tsumo,
            )
        }

        fun decide(view: MahjongStatePayload, seed: ULong = 1uL): MahjongBotMove = MahjongBot.decide(view, SeededSwiftRandom(seed), pastDeadline = { false })

        fun call(windowId: Int, tile: MahjongTile, from: Int, ron: Boolean = false, pon: List<List<MahjongTile>> = emptyList(), chi: List<List<MahjongTile>> = emptyList()) =
            MahjongDecision.Call(windowId, "discard", tile, from, 0.0, 0.0, 0, ron = ron, pon = pon, chi = chi)
    }
}

class MahjongBotTest {
    private val F = MahjongBotFixture

    // ① 없으면: 봇이 myDecision 밖의 패 · 동작을 골라도 손 픽스처 몇 개로는 안 보이고, 엔진이 거절해 연습판이 멎는다.
    @Test
    fun selfPlayDecisionsStayInsideMyDecision() {
        val total = MahjongBotPlay.Tally()
        for (n in 0 until 3) {
            val t = MahjongBotPlay.play(MahjongBotPlay.engine(n), n.toULong() * 7919uL, maxHands = 3)
            total.decisions += t.decisions
            total.claim += t.claim
            total.illegal += t.illegal
        }
        val riichi = MahjongBotPlay.play(MahjongBotPlay.engine(5), 800_000uL, MahjongBotPolicy(defends = true, calls = false), maxHands = 2)
        assertTrue(total.illegal.isEmpty() && riichi.illegal.isEmpty(), (total.illegal + riichi.illegal).take(3).joinToString("\n"))
        assertTrue(total.decisions >= 150, "결정 ${total.decisions}")
        assertTrue(total.claim >= 6, "울기 창 ${total.claim}")
    }

    // 없으면: 봇 넷이 한 판을 끝까지 몰지 못해도(엔진 거절 · 걸음 상한) 모른다.
    @Test
    fun fourBotsFinishATonpuuGame() {
        val e = MahjongTableEngine(MahjongFormat.tonpuu, listOf(null, null, null, null))
        val t = MahjongBotPlay.play(e, 42uL, maxHands = 40)
        assertTrue(t.illegal.isEmpty(), t.illegal.take(3).joinToString("\n"))
        assertTrue(e.isFinished, "판이 끝나지 않음(국 ${t.hands})")
    }

    // ② 없으면: 봇 전용 셈이 규칙 샹텐과 어긋나도 결정 ⊂ myDecision 시험은 초록이다.
    @Test
    fun botShantenMatchesRules() {
        for (part in 0 until 6) {
            val rng = SeededSwiftRandom(4_200uL + part.toULong())
            val calc = MahjongBotShanten()
            val hands = mutableListOf<Pair<IntArray, Int>>()
            for (i in 0 until 14) {
                val melds = i % 3
                val n = 14 - 3 * melds - (i % 2)
                hands += MahjongTiles.counts34(MahjongBotPlay.wall(rng).take(n).map { MahjongTile.of(it)!! }) to melds
            }
            for (text in listOf("1122m3344p5566s7z", "19m19p19s1234567z", "1133557799m1p2p", "11112222333m4m")) {
                hands += MahjongTiles.counts34(MahjongTiles.parse(text)!!) to 0
            }
            for ((c0, m) in hands) {
                val c = c0.copyOf()
                val b = calc.base(c, m)
                assertEquals(MahjongHand.shanten(c, m), b.shanten)
                val delta = if (c.sum() + 3 * m == 14) -1 else 1
                val pr = calc.pairs(b)
                for (k in 0 until 34) {
                    if (!((if (delta < 0) c[k] > 0 else c[k] < 4) && k % 4 == part % 4)) continue
                    val x = c.copyOf().also { it[k] += delta }
                    val want = MahjongHand.shanten(x, m)
                    assertEquals(want, calc.shanten(b, c, k, delta))
                    if (delta < 0) {
                        val derived = calc.removing(b, pr, c, k)
                        assertEquals(want, derived.shanten)
                        val y = x.copyOf()
                        val fresh = calc.base(y, m)
                        val u = IntArray(34) { 4 - y[it] }
                        assertEquals(calc.ukeire(fresh, y, u).second, calc.ukeire(derived, y, u).second)
                    }
                }
                assertTrue(c.contentEquals(c0))
            }
        }
    }

    // 없으면: 유효패가 보이는 장수를 안 빼도 버림 순위가 틀린 채 초록이다.
    @Test
    fun ukeireCountsUnseenTilesOnly() {
        val calc = MahjongBotShanten()
        val c0 = MahjongTiles.counts34(MahjongTiles.parse("1234m5678p99s11z5z")!!)
        val unseen = IntArray(34) { 4 - c0[it] }
        val k4m = MahjongTiles.parse("4m")!![0].kind
        unseen[k4m] = 0
        val c = c0.copyOf()
        val (count, kinds) = calc.ukeire(calc.base(c, 0), c, unseen)
        var naive = 0
        val naiveKinds = mutableListOf<Int>()
        for (k in 0 until 34) {
            if (c0[k] >= 4 || unseen[k] <= 0) continue
            val x = c0.copyOf().also { it[k] += 1 }
            if (MahjongHand.shanten(x, 0) < MahjongHand.shanten(c0, 0)) {
                naive += unseen[k]
                naiveKinds += k
            }
        }
        assertEquals(naive, count)
        assertEquals(naiveKinds, kinds)
        assertTrue(k4m !in kinds && count > 0)
    }

    // ③ 없으면: 리치 상대에게 접는 중이거나 울기 후보가 있을 때 봇이 론 · 쯔모를 넘겨도 모른다.
    @Test
    fun alwaysWins() {
        val f = MahjongBotFixture()
        val hand = f.take("123m456p789s234m5p")
        val riichi = f.seat(2, discards = "1z", riichi = true)
        val dora = f.take("4z")
        val ronTile = f.take("5p")[0]
        val seat1 = f.seat(1).copy(discards = listOf(MahjongDiscard(ronTile, false, false, false)))
        val seats = listOf(f.seat(0), seat1, riichi, f.seat(3))
        fun callView(ron: Boolean) = MahjongBotFixture.view(hand, null, MahjongBotFixture.call(7, ronTile, 1, ron = ron), seats, dora)
        assertEquals(MahjongBotMove.Call(7, MahjongCallAnswer.Ron), MahjongBotFixture.decide(callView(true)))
        assertEquals(MahjongBotMove.Call(7, MahjongCallAnswer.Pass), MahjongBotFixture.decide(callView(false)))
        val g = MahjongBotFixture()
        val h2 = g.take("123m456p789s234m5p")
        val drawn = g.take("5p")[0]
        val seats2 = listOf(g.seat(0), g.seat(1), g.seat(2, discards = "1z", riichi = true), g.seat(3))
        val tsumoView = MahjongBotFixture.view(h2, drawn, MahjongBotFixture.turn(h2, drawn, tsumo = true), seats2, g.take("4z"))
        assertEquals(MahjongBotMove.Act(MahjongTurnAction.Tsumo), MahjongBotFixture.decide(tsumoView))
        val noTsumo = MahjongBotFixture.view(h2, drawn, MahjongBotFixture.turn(h2, drawn, tsumo = false), seats2, emptyList())
        assertNotEquals(MahjongBotMove.Act(MahjongTurnAction.Tsumo), MahjongBotFixture.decide(noTsumo))
    }

    private fun ponView(handText: String, called: String): Pair<MahjongStatePayload, List<MahjongTile>> {
        val f = MahjongBotFixture()
        val hand = f.take(handText)
        val tile = f.take(called)[0]
        val s2 = f.seat(2).copy(discards = listOf(MahjongDiscard(tile, false, false, false)))
        val pair = hand.filter { it.kind == tile.kind }.take(2)
        val v = MahjongBotFixture.view(hand, null, MahjongBotFixture.call(3, tile, 2, pon = listOf(pair)), listOf(f.seat(0), f.seat(1), s2, f.seat(3)), f.take("4z"))
        return v to pair
    }

    // 없으면: 역패(백) 또이츠를 퐁하지 않거나, 역 없는 손님풍 퐁을 해도 모른다. 기준선: 손님풍(남)이면 넘긴다.
    @Test
    fun ponsYakuhaiPairButNotGuestWind() {
        val (haku, pair) = ponView("55z13m579p2468s9s", "5z")
        assertEquals(MahjongBotMove.Call(3, MahjongCallAnswer.Pon(pair)), MahjongBotFixture.decide(haku))
        val (south, _) = ponView("22z13m579p2468s9s", "2z")
        assertEquals(MahjongBotMove.Call(3, MahjongCallAnswer.Pass), MahjongBotFixture.decide(south))
    }

    private fun chiView(handText: String): Pair<MahjongStatePayload, List<MahjongTile>> {
        val f = MahjongBotFixture()
        val hand = f.take(handText)
        val tile = f.take("4m")[0]
        val two = listOf(hand.first { it.token == "2m" }, hand.first { it.token == "3m" })
        val s3 = f.seat(3).copy(discards = listOf(MahjongDiscard(tile, false, false, false)))
        val v = MahjongBotFixture.view(hand, null, MahjongBotFixture.call(5, tile, 3, chi = listOf(two)), listOf(f.seat(0), f.seat(1), f.seat(2), s3), f.take("4z"))
        return v to two
    }

    // 없으면: 샹텐만 줄면 역 없이도 치해 버린다. 기준선: 탕야오 손이면 친다.
    @Test
    fun callsOnlyWithConfirmedYaku() {
        val (tanyao, two) = chiView("23m456p678p34s55s7s")
        assertEquals(MahjongBotMove.Call(5, MahjongCallAnswer.Chi(two)), MahjongBotFixture.decide(tanyao))
        val (noYaku, _) = chiView("23m456p678p34s11s9s")
        assertEquals(MahjongBotMove.Call(5, MahjongCallAnswer.Pass), MahjongBotFixture.decide(noYaku))
    }

    // 없으면: 리치 상대가 있는데 2샹텐 이상인 손이 위험패를 밀어도 모른다. 기준선: 리치가 없으면 현물(5m)을 남긴다.
    @Test
    fun foldsToGenbutsuAgainstRiichiWhenFar() {
        fun view(riichi: Boolean): MahjongStatePayload {
            val f = MahjongBotFixture()
            val hand = f.take("13m5m46p79p24s68s2z")
            val drawn = f.take("3z")[0]
            val s1 = f.seat(1, discards = "5m1z8m", riichi = riichi)
            return MahjongBotFixture.view(hand, drawn, MahjongBotFixture.turn(hand, drawn), listOf(f.seat(0), s1, f.seat(2), f.seat(3)), f.take("4z"))
        }
        val folded = MahjongBotFixture.decide(view(true)) as? MahjongBotMove.Act ?: fail("접기")
        assertEquals("5m", (folded.action as MahjongTurnAction.Discard).tile.token)
        val base = MahjongBotFixture.decide(view(false)) as? MahjongBotMove.Act ?: fail("기준선")
        assertNotEquals("5m", (base.action as MahjongTurnAction.Discard).tile.token)
    }

    private fun noChanceView(handText: String): MahjongStatePayload {
        val f = MahjongBotFixture()
        val hand = f.take(handText)
        val drawn = f.take("8s")[0]
        val s1 = f.seat(1, discards = "4s7p2z", riichi = true)
        val s2 = f.seat(2, melds = listOf(MahjongMeldType.pon to "888m"))
        val s3 = f.seat(3, discards = "8m")
        return MahjongBotFixture.view(hand, drawn, MahjongBotFixture.turn(hand, drawn), listOf(f.seat(0), s1, s2, s3), f.take("1z"))
    }

    // 없으면: 현물이 없을 때 위험도 표(노찬스 1 · 9 < 스지 1 · 9 < … < 무스지)를 안 따라도 모른다.
    @Test
    fun noGenbutsuPrefersNoChanceThenSuji() {
        val a = MahjongBotFixture.decide(noChanceView("2m4m5m7m9m1p2p5p8p9p1s3s6s")) as MahjongBotMove.Act
        assertEquals("9m", (a.action as MahjongTurnAction.Discard).tile.token)
        val b = MahjongBotFixture.decide(noChanceView("1m2m4m5m7m1p2p5p8p9p1s3s6s")) as MahjongBotMove.Act
        assertEquals("1s", (b.action as MahjongTurnAction.Discard).tile.token)
    }

    private fun tenpaiView(handText: String, drawn: String, seen: String = ""): MahjongStatePayload {
        val f = MahjongBotFixture()
        val hand = f.take(handText)
        val d = f.take(drawn)[0]
        val s2 = f.seat(2, discards = seen)
        return MahjongBotFixture.view(hand, d, MahjongBotFixture.turn(hand, d), listOf(f.seat(0), f.seat(1), s2, f.seat(3)), f.take("4z"))
    }

    // 없으면: 멘젠 텐파이에서 리치하지 않거나 가라텐에서 리치해도 모른다.
    @Test
    fun riichiOnLiveTenpaiNotOnKaraten() {
        val live = tenpaiView("123m456p789s34m55p", "2z")
        val r = MahjongBotFixture.decide(live) as MahjongBotMove.Act
        assertEquals("2z", (r.action as? MahjongTurnAction.Riichi)?.tile?.token)
        val dead = MahjongBotFixture.decide(tenpaiView("123m456p789s34m55p", "2z", seen = "222m0555m")) as MahjongBotMove.Act
        assertTrue(dead.action is MahjongTurnAction.Discard, "$dead")
    }

    // 없으면: 리치 없이도 만관 이상인 손에서 리치해 대기를 드러내도 모른다.
    @Test
    fun noRiichiOnManganDama() {
        val v = tenpaiView("123456789m2345m", "9p")
        assertTrue((v.myDecision as MahjongDecision.Turn).riichi.isNotEmpty())
        val move = MahjongBotFixture.decide(v) as MahjongBotMove.Act
        assertTrue(move.action is MahjongTurnAction.Discard, "$move")
    }

    // 없으면: 리치 선언 뒤 나온 패 · 동순 패를 현물로 안 쳐서 덜 안전한 패를 버려도 모른다.
    @Test
    fun genbutsuIncludesTilesPassedAfterRiichiAndSameTurn() {
        val f = MahjongBotFixture()
        val before = f.take("3p")[0]
        val declare = f.take("9m")[0]
        val after = f.take("5s")[0]
        val again = f.take("8p")[0]
        val open1 = f.take("1m")[0]
        val passed = f.take("2m")[0]
        val late = f.take("7z")[0]
        val s1 = f.seat(1, riichi = true).copy(discards = listOf(MahjongDiscard(declare, false, true, false), MahjongDiscard(again, true, false, false)))
        fun ev(seq: Int, kind: String, seat: Int, tile: MahjongTile?, riichi: Boolean = false) = MahjongEvent(seq = seq, kind = kind, seat = seat, tile = tile, riichi = riichi)
        val s3 = f.seat(3).copy(discards = listOf(MahjongDiscard(open1, false, false, false)))
        val base = MahjongBotFixture.view(f.take("123456789s1234p"), null, null, listOf(f.seat(0), s1, f.seat(2), s3), emptyList())
        val events = listOf(
            ev(1, "deal", 0, null), ev(2, "discard", 2, before), ev(3, "discard", 1, declare, riichi = true),
            ev(4, "discard", 2, after), ev(5, "draw", 1, null), ev(6, "discard", 1, again), ev(7, "discard", 3, open1),
            ev(8, "discard", 0, passed), ev(9, "discard", 2, late),
        )
        val v = base.copy(events = events)
        val riichiSafe = MahjongBotRisk.safeKinds(1, v)
        assertTrue(riichiSafe.containsAll(listOf(declare.kind, again.kind, after.kind, open1.kind, passed.kind, late.kind)))
        assertTrue(before.kind !in riichiSafe)
        assertTrue(before.kind in MahjongBotRisk.safeKinds(1, base.copy(events = listOf(ev(10, "discard", 2, before)))))
        assertTrue(MahjongBotRisk.safeKinds(3, v).containsAll(listOf(passed.kind, late.kind)))
        assertTrue(passed.kind !in MahjongBotRisk.safeKinds(3, v.copy(events = events + ev(10, "draw", 3, null))))
        assertTrue(after.kind !in MahjongBotRisk.safeKinds(3, v))
    }

    @Test
    fun noDecisionNoMove() {
        val f = MahjongBotFixture()
        val v = MahjongBotFixture.view(f.take("123m456p789s234m5p"), null, null, listOf(f.seat(0), f.seat(1), f.seat(2), f.seat(3)), emptyList())
        assertEquals(MahjongBotMove.None, MahjongBotFixture.decide(v))
    }

    @Test
    fun thinkSecondsStayInRange() {
        val f = MahjongBotFixture()
        val hand = f.take("123m456p789s234m5p")
        val d = f.take("1z")[0]
        val me = f.seat(0)
        val others = listOf(f.seat(1), f.seat(2), f.seat(3))
        val v = MahjongBotFixture.view(hand, d, MahjongBotFixture.turn(hand, d), listOf(me) + others, emptyList())
        val riichiView = MahjongBotFixture.view(hand, d, MahjongBotFixture.turn(hand, d, riichiOK = false), listOf(me.copy(riichi = true)) + others, emptyList())
        val rng = SeededSwiftRandom(9uL)
        val discard = MahjongBotMove.Act(MahjongTurnAction.Discard(d))
        repeat(200) {
            val s = MahjongBot.thinkSeconds(discard, v, rng)
            assertTrue(s in 0.6..1.2, "$s")
        }
        assertEquals(0.4, MahjongBot.thinkSeconds(discard, riichiView, rng))
        assertEquals(0.0, MahjongBot.thinkSeconds(MahjongBotMove.Call(1, MahjongCallAnswer.Pass), v, rng))
        assertEquals(0.0, MahjongBot.thinkSeconds(MahjongBotMove.None, v, rng))
    }

    // ④ 없으면: 2단 보기가 마감을 안 보면 느린 기기에서 봇이 200ms 를 훌쩍 넘긴다. 기준선: 마감이 멀면 2단 결과(1단과 다르다).
    @Test
    fun slowClockFallsBackToOneStep() {
        val f = MahjongBotFixture()
        val hand = f.take("1m2m3m5m6m7p4s0s5s6s6s7s9s")
        val drawn = f.take("2m")[0]
        val view = MahjongBotFixture.view(hand, drawn, MahjongBotFixture.turn(hand, drawn), listOf(f.seat(0), f.seat(1), f.seat(2), f.seat(3)), f.take("4z"))
        val oneStep = MahjongBot.decide(view, SeededSwiftRandom(1uL), pastDeadline = { true })
        val twoStep = MahjongBot.decide(view, SeededSwiftRandom(1uL), pastDeadline = { false })
        assertNotEquals(oneStep, twoStep)
        var ticks = 0
        val move = MahjongBot.decide(view, SeededSwiftRandom(1uL), pastDeadline = { ticks += 1; ticks * 100 >= 200 })
        assertEquals(oneStep, move)
        assertTrue(ticks in 2..3, "ticks $ticks")
        assertTrue(MahjongBotPlay.isLegal(move, view.myDecision))
    }
}
