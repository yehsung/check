// 원본: 없음 — W4-b 완료 기준 ①(G §2-3): "대본 판을 UI 루프로 재생하면 제출 본문이 골든과 같다(스텁)".
//
// UI 루프 = 이 갈래가 만든 [GamesMiniGameCanvasHost] 통째(프레임 루프 MiniGameFrameLoop + 페이서 + 손가락 pointerInput + 그림)다. 시험은
// 오프스크린 장면(ImageComposeScene — 창 없음, java.awt.headless)에 그것을 세우고, 골든 대본(W1-a `timing-bar/scripted` · `flappy/scripted` —
// Swift 엔진이 낸 정답)의 연산을 **손가락 누름**으로, 프레임을 **장면 렌더 시각**으로 넣는다. 엔진을 직접 부르지 않는다.
// 서버는 스텁(MockEngine — 망 0)이고, 허브(W2-e GamesMiniGameHub)가 낸 제출 요청의 본문·모양을 골든 둘과 대조한다:
//   · 마지막 판 점수 = 대본 골든의 final.total(Swift 엔진이 그 대본으로 낸 총점) · 라운드 점수 열 = final.roundScores
//   · 끝난 판마다 제출 한 번 · 판마다 새 토큰(t1 · t2 …) — 허브의 토큰 규칙(기억 minigame-round-token-race)이 UI 루프를 지나서도 선다
//   · 요청 모양 = W1-d 요청 골든 `wire/requests` 의 submitMiniGameScore(경로 · 방식 · 본문 열쇠 · 머리 이름)
//
// 어느 대본을 쓰나(전부 Swift 엔진 골든이다):
//   · 타이밍 바 B — 판을 네 번 켜고(결과 뒤 다시) 마지막 판이 10라운드 결과 표시에서 대본이 끝난다 → 꼬리 프레임으로 끝내 제출 넷.
//   · 플래피 B·C — 판이 여러 번 끝나고 다시 켜진다(끝난 판마다 제출) · 대본 끝은 진행 중(점수·날갯짓 수를 final 과 대조).
//   · 뺀 것: 프레임 간격이 엔진 클램프(maxStep 1/30초) **아래**인 대본(타이밍 바 A·D · 플래피 A·D) — 화면 프레임 시계는 정수 나노초라
//     1/60·1/120 초를 비트 그대로 못 내고, 그 대본은 탭이 점수 반올림 경계 1e-9초 안에 놓인 곳이 있어 나노초 반올림 하나로 점수가 갈린다
//     (실측: 타이밍 바 A 1라운드 98 → 99 · 플래피 A 점수 4 → 1 — 엔진만으로 같은 dt 열을 돌려도 같다). 클램프 이상 대본은 렌더 간격을 dt 를
//     **올림한 나노초**로 주면 엔진이 매 걸음을 정확히 maxStep 으로 받아 비트까지 같아진다. 타이밍 바 C 는 맥 전용 연산 'V'(창 닫힘 무효)가 있어
//     폰 손가락으로 낼 수 없다 · 플래피 E 는 고정 시작판이라 화면이 만들 수 없다.
//
// UI 루프가 대본과 다른 점은 **시작 지연** 하나다: 판이 켜지는 탭 뒤 프레임 루프가 다시 서는 데 렌더 몇 장(오프스크린 장면에서 3 — 효과 기동 ·
// 기준 프레임 · 첫 걸음)이 든다(Swift TimelineView 도 기준 프레임을 쓴다 — GamesPlayController.tick "시작 뒤 첫 프레임은 기준만 잡는다").
// 그래서 판이 켜질 때마다 **엔진이 처음 한 걸음 움직인 렌더**를 그 대본 프레임의 걸음으로 맞추고(지연이 3장 안인지도 잰다), 그 뒤로는 렌더
// 한 장 = 대본 한 프레임이다 — 페이서가 프레임을 거르거나 겹치면 판 시계가 대본과 갈라 라운드 점수가 바뀐다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
class MiniGameScriptedReplayTest {
    private val timingGolden = Golden.load("timing-bar/scripted")
    private val flappyGolden = Golden.load("flappy/scripted")
    private val wireGolden = Golden.load("wire/requests")

    /** 재생 한 판의 결과. */
    private data class Replay(val startLatency: Int, val starts: Int, val controller: GamesPlayController, val submits: List<String>, val submitHeaders: List<Set<String>>, val method: String?, val path: String?)

    private fun JsonObject.str(key: String): String = getValue(key).jsonPrimitive.content

    /**
     * 렌더 간격(나노초) = 대본 dt 를 **올림**한 값. 엔진 클램프(maxStep) 이상인 대본만 받는다 — 그래야 엔진이 받는 걸음이 비트까지 대본과 같다(머리말).
     * 장면 주사율은 60 — 페이서 최소 간격(16.5ms)이 렌더 간격보다 짧아 렌더 한 장마다 틱이 선다.
     */
    private fun frameNanos(dt: Double, maxStep: Double): Long {
        check(dt >= maxStep) { "dt $dt 는 엔진 클램프($maxStep) 아래 — 나노초 프레임 시계로 비트 재생 불가(머리말)" }
        return kotlin.math.ceil(dt * 1_000_000_000.0).toLong()
    }

    /** 장면 가운데를 손가락으로 한 번 누르고 뗀다. */
    private fun ImageComposeScene.tap() {
        sendPointerEvent(PointerEventType.Press, Offset(WIDTH_PX / 2f, HEIGHT_PX / 2f), type = PointerType.Touch)
        sendPointerEvent(PointerEventType.Release, Offset(WIDTH_PX / 2f, HEIGHT_PX / 2f), type = PointerType.Touch)
    }

    /**
     * 대본 한 판을 UI 루프로 민다. [prepare] 가 허브 구동기에 대본의 시작 판(시드)을 넣는다(Swift `replaceForTesting` 과 같은 시험 문).
     * [moved] 는 "엔진이 한 걸음 움직였는가" — 시작 정렬에 쓴다. [skipTapAt] 은 음성 기준선(그 프레임 누름 하나를 뺀다).
     */
    private suspend fun TestScope.replay(
        kind: MiniGameKind,
        case: JsonObject,
        prepare: (GamesPlayController) -> Unit,
        moved: (GamesPlayController) -> Boolean,
        finished: (GamesPlayController) -> Boolean,
        tapOp: String,
        maxStep: Double,
        skipTapAt: Int? = null,
    ): Replay {
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        try {
            h.signIn()
            val store = GamesStore(h.context)
            val hub = store.miniGames
            hub.openScreen(kind)
            advanceUntilIdle()
            val controller = requireNotNull(hub.controller)
            prepare(controller)
            val dt = Golden.bits(case.str("dtBits"))
            val step = frameNanos(dt, maxStep)
            val refresh = 60
            val frames = ScriptOps.decode(case.str("ops"))
            val scene = ImageComposeScene(WIDTH_PX, HEIGHT_PX, Density(DENSITY)) {
                AingTheme(dark = true) { GamesMiniGameCanvasHost(controller, 0L, refresh, MiniGameArt.empty, Modifier.fillMaxSize()) }
            }
            val latencies = mutableListOf<Int>()
            try {
                var k = 0L
                fun render() {
                    scene.render(k * step)
                    k += 1
                    // 렌더 사이에 스텁 왕복을 끝낸다(지금 가상 시각에 걸린 일만 — 시계를 앞으로 돌리지 않는다). 실제 판 사이에도 왕복은 끝나 있다.
                    testScheduler.runCurrent()
                }
                render()
                for (f in frames.indices) {
                    var stepped = false
                    for (op in frames[f]) {
                        check(op == tapOp) { "UI 가 낼 수 없는 연산 '$op'(프레임 $f)" }
                        check(!stepped) { "판을 켠 누름 뒤 같은 프레임에 연산이 또 있다(프레임 $f) — 이 재생은 그 순서를 못 낸다" }
                        val wasPlaying = controller.isPlaying
                        if (f != skipTapAt) scene.tap()
                        if (!wasPlaying && controller.isPlaying) {
                            // 판이 켜졌다(시작 · 결과 뒤 다시) — 엔진이 첫 걸음을 뗄 때까지 렌더한다. 그 렌더가 이 프레임의 걸음이다.
                            var n = 0
                            while (!moved(controller)) {
                                render()
                                n += 1
                                check(n <= 4) { "판이 켜진 뒤 렌더 ${n}장 동안 엔진이 한 걸음도 안 움직였다(프레임 $f)" }
                            }
                            latencies += n
                            stepped = true
                        }
                    }
                    if (!stepped) render()
                }
                var extra = 0
                while (!finished(controller) && extra < MAX_TAIL_FRAMES) {
                    render()
                    extra += 1
                }
                advanceUntilIdle()
            } finally {
                scene.close()
            }
            val submits = h.server.requests.filter { it.rpcName == "minigame_submit_score" }
            return Replay(
                startLatency = latencies.maxOrNull() ?: -1,
                starts = latencies.size,
                controller = controller,
                submits = submits.map { it.bodyText },
                submitHeaders = submits.map { r -> r.headers.keys.map { it.lowercase() }.toSet() },
                method = submits.firstOrNull()?.method,
                path = submits.firstOrNull()?.path,
            )
        } finally {
            h.close()
        }
    }

    private fun timingCase(id: String): JsonObject = timingGolden.cases.first { it.str("id") == id }
    private fun flappyCase(id: String): JsonObject = flappyGolden.cases.first { it.str("id") == id }

    private suspend fun TestScope.replayTiming(id: String, skipTapAt: Int? = null): Replay {
        val case = timingCase(id)
        val seed = Golden.hex64(case.str("seed"))
        return replay(
            MiniGameKind.timingBar, case,
            prepare = { it.seedTiming(seed) },
            moved = { c -> ((c.timing.phase as? TimingBarGame.Phase.Running)?.t ?: 0.0) > 0.0 },
            finished = { c -> c.timing.phase is TimingBarGame.Phase.Finished },
            tapOp = "T",
            maxStep = TimingBarGame.maxStep,
            skipTapAt = skipTapAt,
        )
    }

    /** 요청 골든의 제출 모양(경로 · 방식 · 본문 열쇠 · 머리 이름). */
    private fun goldenSubmitShape(): Triple<Pair<String, String>, Set<String>, Set<String>> {
        val request = wireGolden.cases.first { it.str("id") == "submitMiniGameScore" }["requests"]!!.let { it as kotlinx.serialization.json.JsonArray }[0].jsonObject
        val body = request["body"]!!.jsonObject.keys
        val headers = request["headers"]!!.jsonObject.keys
        return Triple(request.str("method") to request.str("path"), body, headers)
    }

    @Test
    fun timingBarScriptedRoundsSubmitTheGoldenTotalThroughTheUiLoop() = runTest {
        val (route, bodyKeys, headerNames) = goldenSubmitShape()
        for (id in listOf("B")) {
            val case = timingCase(id)
            val final = case["final"]!!.jsonObject
            val wantScores = final.str("roundScores").split(' ').map { it.toInt() }
            val wantTotal = final.getValue("total").jsonPrimitive.int
            val replay = replayTiming(id)
            assertTrue(replay.startLatency in 1..3, "대본 $id: 시작 지연 렌더 ${replay.startLatency}장")
            assertEquals(wantScores, replay.controller.timing.roundScores, "대본 $id: 라운드 점수 열(UI 루프 재생 ≠ Swift 엔진 골든)")
            assertEquals(TimingBarGame.Phase.Finished(wantTotal), replay.controller.timing.phase, "대본 $id: 10라운드를 다 돌고 끝나야 제출한다")
            // 대본이 판을 몇 번 다시 켰는가(결과 뒤 누름) — 끝난 판마다 제출이 한 번이고, 마지막 판의 총점이 골든 final.total 이다.
            assertEquals(replay.starts, replay.submits.size, "대본 $id: 제출은 끝난 판마다 한 번 — 켠 판 ${replay.starts} · 제출 ${replay.submits}")
            val tokens = replay.submits.map { Json.parseToJsonElement(it).jsonObject.str("p_token") }
            assertEquals((1..replay.submits.size).map { "t$it" }, tokens, "대본 $id: 판마다 새 토큰(한 토큰에 한 점수)")
            val body = Json.parseToJsonElement(replay.submits.last()).jsonObject
            assertEquals(bodyKeys, body.keys, "대본 $id: 제출 본문 열쇠가 요청 골든과 다르다")
            assertEquals("timing_bar", body.str("p_game"))
            assertEquals(wantTotal.toLong(), body.getValue("p_score").jsonPrimitive.long, "대본 $id: 제출 점수 = 골든 총점")

            assertEquals(route, replay.method to replay.path, "대본 $id: 제출 경로·방식이 요청 골든과 다르다")
            assertTrue(replay.submitHeaders.all { it.containsAll(headerNames) }, "대본 $id: 요청 골든의 머리($headerNames)가 빠졌다 — ${replay.submitHeaders}")
        }
    }

    @Test
    fun theStartLatencyIsAtMostThreeRenders() = runTest {
        // 시작 탭 → 엔진 첫 걸음까지 렌더 수(오프스크린 장면 실측 3: 효과 기동 · 기준 프레임 · 첫 걸음). 이 수가 늘면 탭한 뒤 판이 눈에 띄게
        // 늦게 움직인다(60Hz 에서 렌더 한 장 = 16.7ms). 판의 공정성과는 무관하다 — 판 시계는 기준 프레임에서 시작한다.
        val case = timingCase("A")
        val seed = Golden.hex64(case.str("seed"))
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        try {
            h.signIn()
            val hub = GamesStore(h.context).miniGames
            hub.openScreen(MiniGameKind.timingBar)
            advanceUntilIdle()
            val controller = requireNotNull(hub.controller)
            controller.seedTiming(seed)
            val scene = ImageComposeScene(WIDTH_PX, HEIGHT_PX, Density(DENSITY)) {
                AingTheme(dark = true) { GamesMiniGameCanvasHost(controller, 0L, 60, MiniGameArt.empty, Modifier.fillMaxSize()) }
            }
            try {
                var k = 0L
                scene.render(0L)
                scene.tap()
                var renders = 0
                while (((controller.timing.phase as? TimingBarGame.Phase.Running)?.t ?: 0.0) == 0.0) {
                    k += 1
                    scene.render(k * 16_666_667L)
                    renders += 1
                    check(renders <= 10)
                }
                assertTrue(renders in 1..3, "시작 지연 렌더 $renders 장")
            } finally {
                scene.close()
            }
        } finally {
            h.close()
        }
    }

    @Test
    fun aDroppedTapChangesTheRoundScores() = runTest {
        // 음성 기준선(기억 comparison-baseline-must-differ): 같은 대본에서 판정 누름 하나만 빼면 라운드 점수 열이 골든과 달라야 한다 —
        // 위 대조가 손가락 입력을 실제로 본다는 증거다.
        val case = timingCase("B")
        val frames = ScriptOps.decode(case.str("ops"))
        // 대본 B 는 판을 다시 켠다 — final 은 **마지막 판**의 점수다. 그 판에서 **실제로 판정한** 마지막 누름 하나를 뺀다(결과 표시 중 누름은
        // 엔진이 버리므로 빼도 같다). 어느 누름이 판정했는지는 엔진(골든으로 잠긴 core 규칙)을 대본대로 돌려 찾는다.
        val seed = Golden.hex64(case.str("seed"))
        val dt = Golden.bits(case.str("dtBits"))
        val engine = TimingBarGame(seed)
        var lastJudged = -1
        frames.forEachIndexed { f, ops ->
            for (op in ops) {
                val wasRunning = engine.phase is TimingBarGame.Phase.Running
                engine.tap()
                if (wasRunning && engine.phase is TimingBarGame.Phase.RoundResult) lastJudged = f
            }
            engine.step(dt)
        }
        val replay = replayTiming("B", skipTapAt = lastJudged)
        val wantScores = case["final"]!!.jsonObject.str("roundScores").split(' ').map { it.toInt() }
        assertNotEquals(wantScores, replay.controller.timing.roundScores)
    }

    @Test
    fun flappyScriptedRunsReachTheGoldenScoreThroughTheUiLoop() = runTest {
        // 플래피 대본은 진행 중에 끝난다(제출 없음 — 폰에서 끝나지 않은 플래피 판은 기록하지 않는다). UI 루프가 낸 판 상태(점수 · 날갯짓 수)를
        // Swift 엔진 골든의 final 과 대조한다. A·D 는 dt 가 클램프 아래라 뺀다(머리말) · E(고정 시작판)는 시작판을 화면이 만들 수 없어 뺀다.
        for (id in listOf("B", "C")) {
            val case = flappyCase(id)
            val seed = Golden.hex64(case.str("seed"))
            val final = case["final"]!!.jsonObject
            val replay = replay(
                MiniGameKind.flappy, case,
                prepare = { it.seedFlappy(seed) },
                moved = { c -> c.flappy.elapsed > 0.0 },
                finished = { true },
                tapOp = "F",
                maxStep = FlappyGame.maxStep,
            )
            assertEquals(final.getValue("score").jsonPrimitive.int, replay.controller.flappy.score, "플래피 대본 $id: 점수")
            assertEquals(final.getValue("flapCount").jsonPrimitive.int, replay.controller.flappy.flapCount, "플래피 대본 $id: 날갯짓 수")
            assertTrue(replay.controller.flappy.phase == FlappyGame.Phase.Running, "플래피 대본 $id: 대본 끝은 진행 중(골든 phase running)")
            // 결과까지 간 판(게임오버 → 결과)마다 제출 한 번 · 마지막 판은 진행 중이라 제출이 없다.
            assertEquals(replay.starts - 1, replay.submits.size, "플래피 대본 $id: 켠 판 ${replay.starts} · 제출 ${replay.submits}")
            val tokens = replay.submits.map { Json.parseToJsonElement(it).jsonObject.str("p_token") }
            assertEquals((1..replay.submits.size).map { "t$it" }, tokens, "플래피 대본 $id: 판마다 새 토큰")
        }
    }

    /**
     * 구동기에 대본의 시작판(시드)을 넣는다. **두 번 넣는다** — 구동기의 판은 Compose 상태(mutableStateOf · 구조 동등 정책)이고 엔진의 equals 는
     * 난수 상태를 비교하지 않는다(Swift `==` 와 같다). 그래서 허브가 막 만든 시작 전 판(다른 시드)과 대본의 시작 전 판은 **같은 값**으로 보여 한 번
     * 넣으면 쓰기가 버려진다(이 시험이 처음 그 꼴로 빨갰다 — 보고 unresolved: W2-e 구동기 상태 정책). 다른 값(시작한 판)을 먼저 넣으면 그다음 쓰기는 산다.
     */
    private fun GamesPlayController.seedTiming(seed: ULong) {
        replaceForTesting(timing = TimingBarGame(seed).also { it.tap() })
        replaceForTesting(timing = TimingBarGame(seed))
        val probe = timing.copy().also { it.tap() }
        val ref = TimingBarGame(seed).also { it.tap() }
        check(timing.phase == TimingBarGame.Phase.Ready && probe.target == ref.target) { "대본 시작판(시드)이 안 들어갔다" }
    }

    private fun GamesPlayController.seedFlappy(seed: ULong) {
        replaceForTesting(flappy = FlappyGame(seed).also { it.flap() })
        replaceForTesting(flappy = FlappyGame(seed))
        val probe = flappy.copy().also { it.flap() }
        val ref = FlappyGame(seed).also { it.flap() }
        check(flappy.phase == FlappyGame.Phase.Ready && probe.pipes == ref.pipes) { "대본 시작판(시드)이 안 들어갔다" }
    }

    private companion object {
        const val DENSITY = 2f
        const val WIDTH_PX = 584
        const val HEIGHT_PX = 604
        const val MAX_TAIL_FRAMES = 600
    }
}
