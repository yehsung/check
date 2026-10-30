package com.yehsung.aingcheck.desktop.overlay.engine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Kotlin 우선순위·길이·말풍선 초 == 저장소 motion.json(굽기가 Swift ReactionKind 에서 읽어 낸 표). */
class MotionTableContractTest {
    private fun motionJson(): File {
        // W-6 #5(W5-b1 P2): 저장소 뿌리는 시험 봉인(aingcheck.test-seal)이 넘기는 aingcheck.repoRoot 하나 — user.dir 걷기 대체 경로는 걷었다.
        val root = requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)" }
        return File(root, "multiplatform/assets/aing-bake/motion.json").also { check(it.isFile) { "motion.json 이 없다: $it" } }
    }

    private val samples = listOf(
        ReactionKind.Hit, ReactionKind.CommuteStart, ReactionKind.CommuteEnd, ReactionKind.Milestone,
        ReactionKind.Greeting("a"), ReactionKind.Poked("p"), ReactionKind.UltraPoked("u"), ReactionKind.GoalAchieved,
        ReactionKind.UltraCharged, ReactionKind.RubyReward(3), ReactionKind.Drowsy, ReactionKind.Wake,
    )

    @Test fun kotlinReactionTableMatchesRepoMotionJson() {
        val root = Json.parseToJsonElement(motionJson().readText()).jsonObject
        val reactions = root.getValue("reactions").jsonArray.map { it.jsonObject }
            .associateBy { it.getValue("name").jsonPrimitive.content }
        fun JsonObject.num(k: String): Double? = this[k]?.takeIf { it !is JsonNull }?.jsonPrimitive?.doubleOrNull
        for (k in samples) {
            val spec = assertNotNull(reactions[k.motionName], "motion.json 에 ${k.motionName} 이 없다")
            assertEquals(spec["priority"]?.jsonPrimitive?.intOrNull, k.priority, "${k.motionName} priority")
            assertEquals(spec.num("durationS"), k.duration, "${k.motionName} durationS")
            assertEquals(spec.num("bubbleSeconds"), ReactionRules.bubbleSeconds(k), "${k.motionName} bubbleSeconds")
        }
        val covered = samples.map { it.motionName }.toSet() + "quietRise" // quietRise 는 CharacterPlayer.wake(quiet) 몫
        assertEquals(reactions.keys, covered, "motion.json 에 새 리액션이 생기면 ReactionKind 도 같이")
        val engine = root.getValue("engine").jsonObject
        assertEquals(engine.num("hitCooldownS"), ReactionRules.HIT_COOLDOWN_S)
    }
}

class TeammateGreetingDetectorTest {
    private fun m(id: String, working: Boolean) = TeamPresence(id, "이름$id", working)

    @Test fun greetingDetectorExcludesFirstLoadAndSelfAndAppliesCooldown() {
        val d = TeammateGreetingDetector()
        assertEquals(emptyList(), d.detect(listOf(m("a", true), m("b", false), m("me", false)), "me", 0.0), "첫 로드 침묵")
        assertEquals(listOf("이름b"), d.detect(listOf(m("a", true), m("b", true), m("me", true)), "me", 10.0), "offWork→working 만, 자기 제외")
        d.detect(listOf(m("b", false)), "me", 20.0)
        assertEquals(emptyList(), d.detect(listOf(m("b", true)), "me", 10.0 + 599.0), "10분 쿨다운")
        d.detect(listOf(m("b", false)), "me", 700.0)
        assertEquals(listOf("이름b"), d.detect(listOf(m("b", true)), "me", 10.0 + 600.0 + 100.0))
        assertEquals(emptyList(), d.detect(listOf(m("new", true)), "me", 800.0), "처음 보는 근무자(nil→working)는 인사하지 않는다")
        d.reset()
        assertEquals(emptyList(), d.detect(listOf(m("b", false)), "me", 900.0), "로그아웃 뒤 첫 목록은 다시 시드")
    }

    @Test fun directorGreetsOnlyWhileVisible() {
        val f = Fixture()
        f.d.onTeam(listOf(TeamPresence("b", "민수", false)), "me", 0.0)
        val t = f.working()
        f.d.onTeam(listOf(TeamPresence("b", "민수", true)), "me", t)
        assertEquals("민수님 출근!", f.d.bubbleAt(t)?.text)
    }
}

class ClickRoutingTest {
    private val p = OverlayPoint(1800.0, 100.0)

    private fun click(f: Fixture, now: Double, target: HitTarget = HitTarget.Body): PointerOutcome {
        f.d.onPointer(PointerKind.DOWN, p, target, now)
        return f.d.onPointer(PointerKind.UP, p, target, now + 0.05)
    }

    @Test fun overlayControllerReactsToClickInsidePanelOnly_andHitCooldown() {
        val f = Fixture()
        val t = f.working()
        assertEquals(ClickAction.None, click(f, t, HitTarget.None).click)
        assertEquals(ClickAction.Hit, click(f, t + 1).click)
        assertEquals(ClickAction.None, click(f, t + 1.2).click, "쿨다운 안")
    }

    @Test fun overlayWakesOnDownUpClickWhileSleeping_insteadOfHit() {
        val f = Fixture()
        val t = f.working()
        f.d.request(ReactionKind.Drowsy, t)
        assertEquals(ClickAction.Wake, click(f, t + 1).click)
        assertEquals(ReactionKind.Wake, f.d.activeReaction(t + 1.1))
    }

    @Test fun boardEnabledClickTogglesBoard_notHit() {
        val f = Fixture(boardEnabled = true)
        val t = f.working()
        assertEquals(ClickAction.ToggleBoard, click(f, t).click)
        assertEquals(listOf("toggle:true"), f.board.calls)
        assertTrue(f.sink.calls.last() == "facing:-1,false", "열린 보드 쪽을 본다")
        f.d.tick(f.d.nextDrowsyAtForTest!!)
        assertTrue(!f.d.isSleeping, "보드가 열려 있으면 졸지 않는다")
    }

    @Test fun hiddenOrUltraIgnoresPointer() {
        val f = Fixture()
        assertEquals(ClickAction.None, click(f, 1.0).click)
        val t = f.working()
        f.d.onPokes(listOf(poke("u", "민수", com.yehsung.aingcheck.core.wire.models.PokeKind.ultra)), t)
        assertEquals(ClickAction.None, click(f, t + 1).click)
    }

    @Test fun overlaySmallMoveIsTreatedAsClick_largeMoveDragsWithoutHit() {
        val f = Fixture()
        val t = f.working()
        f.d.onPointer(PointerKind.DOWN, p, HitTarget.Body, t)
        assertNull(f.d.onPointer(PointerKind.DRAG, OverlayPoint(p.x + 3.0, p.y + 2.0), HitTarget.Body, t + 0.01).moveTo, "4 이하는 드래그 아님")
        assertEquals(ClickAction.Hit, f.d.onPointer(PointerKind.UP, OverlayPoint(p.x + 3.0, p.y + 2.0), HitTarget.Body, t + 0.02).click)
        val g = Fixture()
        val u = g.working()
        val start = OverlayGeometry.defaultFrame(Mon.primary.work)
        g.d.onPointer(PointerKind.DOWN, p, HitTarget.Body, u)
        val moved = g.d.onPointer(PointerKind.DRAG, OverlayPoint(p.x - 50.0, p.y + 20.0), HitTarget.Body, u + 0.01)
        assertEquals(OverlayPoint(start.left - 50.0, start.top + 20.0), moved.moveTo)
        assertEquals("facing:-1,true", g.sink.calls.last(), "가는 방향·걷기")
        val up = g.d.onPointer(PointerKind.UP, OverlayPoint(p.x - 50.0, p.y + 20.0), HitTarget.Body, u + 0.02)
        assertEquals(ClickAction.None, up.click)
        assertEquals(OverlayPlacement("DISPLAY1", 24.0 + 50.0, 24.0 + 20.0), up.savePlacement)
        assertEquals("facing:0,false", g.sink.calls.last(), "놓으면 걷기 멈춤·정면")
    }

    @Test fun overlayDragFacingIgnoresMicroJitter_andNewMouseDownResetsFacing() {
        val h = DragFacingHysteresis()
        h.begin(100.0)
        assertEquals(0, h.update(102.9))
        assertEquals(1, h.update(104.0))
        assertEquals(1, h.update(101.5), "기준점 104 에서 −2.5 는 손떨림")
        assertEquals(-1, h.update(100.9))
        h.reset()
        assertEquals(0, h.direction)
        val f = Fixture()
        val t = f.working()
        f.d.onPointer(PointerKind.DOWN, p, HitTarget.Body, t)
        assertEquals("facing:0,false", f.sink.calls.last())
    }

    @Test fun dragIsClampedToTheWorkArea_andRepositionsAnOpenBoard() {
        val f = Fixture(boardEnabled = true)
        val t = f.working()
        f.board.open = true
        f.d.onPointer(PointerKind.DOWN, p, HitTarget.Body, t)
        val out = f.d.onPointer(PointerKind.DRAG, OverlayPoint(p.x + 100.0, p.y - 500.0), HitTarget.Body, t + 0.01)
        assertEquals(OverlayPoint(Mon.primary.work.right - OverlayGeometry.PANEL_WIDTH, 0.0), out.moveTo)
        assertTrue("reposition" in f.board.calls)
        f.d.onPointer(PointerKind.UP, OverlayPoint(p.x + 100.0, p.y - 500.0), HitTarget.Body, t + 0.02)
        assertEquals("facing:-1,false", f.sink.calls.last(), "보드가 열려 있으면 정면 복귀 대신 보드 쪽")
    }
}

class PlacementTest {
    private val monitors = listOf(Mon.primary, Mon.second)

    @Test fun overlayFrameSitsAtTopRightWithMargin() {
        assertEquals(OverlayRect(1920.0 - 140 - 24, 24.0, 140.0, 170.0), OverlayGeometry.defaultFrame(Mon.primary.work))
        assertEquals(OverlayGeometry.defaultFrame(Mon.primary.work), OverlayGeometry.restore(null, monitors, Mon.primary.work))
    }

    @Test fun overlayDragOffsetRoundTripsAcrossMonitors() {
        val frame = OverlayRect(3000.0, 100.0, 140.0, 170.0)
        val saved = assertNotNull(OverlayGeometry.capture(frame, monitors))
        assertEquals(OverlayPlacement("DISPLAY2", 4480.0 - 3140.0, 100.0), saved)
        assertEquals(frame, OverlayGeometry.restore(saved, monitors, Mon.primary.work))
    }

    @Test fun missingMonitorFallsBackToPrimaryWithSameOffsets_andClamps() {
        val saved = OverlayPlacement("DISPLAY2", 1340.0, 100.0)
        assertEquals(OverlayRect(440.0, 100.0, 140.0, 170.0), OverlayGeometry.restore(saved, listOf(Mon.primary), Mon.primary.work))
        val far = OverlayPlacement("DISPLAY1", 5000.0, 5000.0)
        assertEquals(OverlayRect(0.0, 1040.0 - 170.0, 140.0, 170.0), OverlayGeometry.restore(far, monitors, Mon.primary.work))
    }

    @Test fun clampedOriginKeepsPanelInsideVisibleFrame() {
        val work = OverlayRect(0.0, 0.0, 100.0, 100.0)
        assertEquals(OverlayPoint(0.0, 0.0), OverlayGeometry.clampedOrigin(-50.0, 50.0, 140.0, 170.0, work), "창이 더 크면 왼쪽 위")
        assertEquals(OverlayPoint(60.0, 30.0), OverlayGeometry.clampedOrigin(90.0, 30.0, 40.0, 40.0, work))
    }

    @Test fun monitorNearAndCanRestore() {
        val off = OverlayRect(-500.0, -500.0, 140.0, 170.0)
        assertTrue(!OverlayGeometry.canRestore(off, monitors))
        assertTrue(OverlayGeometry.canRestore(OverlayRect(1900.0, 10.0, 140.0, 170.0), monitors))
        val straddle = OverlayRect(1870.0, 10.0, 140.0, 170.0)
        assertEquals("DISPLAY2", OverlayGeometry.monitorNear(OverlayPoint(-1.0, -1.0), straddle, monitors)?.key, "더 많이 겹치는 쪽")
    }
}

/** 가짜 측정기로 갈래 판정 ①~④ · 이름 6자+폭 · 줄바꿈 접기 · 40자 안전망. */
class BubbleFormTest {
    private val m = FakeMeasure()

    @Test fun inlineWhenItFits() {
        assertEquals(BubbleForm.Form.Inline("민수님: 안녕"), BubbleForm.of("민수", "안녕", m))
    }

    @Test fun rule1_noInkMeansArrival() {
        assertIs<BubbleForm.Form.Arrival>(BubbleForm.of("민수", "  \n ", m))
        assertIs<BubbleForm.Form.Arrival>(BubbleForm.of("민수", "️", m), "그릴 글리프가 없는 본문")
    }

    @Test fun rule2_safetyNetCatchesWhatWidthCannotSee() {
        val thin = FakeMeasure(latin = 1.0)
        assertIs<BubbleForm.Form.Inline>(BubbleForm.of("a", "x".repeat(40), thin))
        assertIs<BubbleForm.Form.Arrival>(BubbleForm.of("a", "x".repeat(41), thin), "폭은 맞아도 41 글자소면 도착")
        assertEquals(1, BubbleForm.graphemeCount("👍🏽"))
    }

    @Test fun rule3_capsuleIsTwoLinesAndEveryCjkWordFitsOneLine() {
        assertIs<BubbleForm.Form.Inline>(BubbleForm.of("민수", "오늘 점심 같이 먹어요", m))
        assertIs<BubbleForm.Form.Arrival>(BubbleForm.of("민수", "오늘 점심 같이 먹어요 저녁도 같이 먹어요", m), "3줄")
        val oneLiner = object : BubbleTextMeasure {
            override fun width(t: String) = m.width(t)
            override fun lineCount(t: String, widthPt: Double) = 1
        }
        assertIs<BubbleForm.Form.Arrival>(BubbleForm.of("민수", "가나다라마바사아자차", oneLiner), "한 낱말이 한 줄보다 넓으면 도착")
    }

    @Test fun rule4_arrivalNoticeIsNeverMistakenForSpokenBody() {
        val out = BubbleForm.of("✉️ 철수", "님 메시지 도착!", m)
        assertIs<BubbleForm.Form.Arrival>(out)
        assertTrue(BubbleForm.isArrival(out.text))
    }

    @Test fun messageBubbleNameKeepsItsOwnWidthBudget() {
        assertEquals("가나다라마바…", BubbleForm.clippedName("가나다라마바사", m), "6자")
        assertEquals("ABCD…", BubbleForm.clippedName("ABCDEFGH", FakeMeasure(latin = 14.0)), "넓은 글자는 6자 전에 폭으로")
        assertEquals("", BubbleForm.clippedName("", m))
        assertEquals("✉️ 가나다라마바… 님 메시지 도착!".replace(" 님", "님"), BubbleForm.arrivalText(BubbleForm.clippedName("가나다라마바사", m)))
    }

    @Test fun messageBubbleFoldsNewlinesInsteadOfBlowingTheBudget() {
        assertEquals("안녕 잘 지내?", BubbleForm.flattened("안녕\n\n잘 지내?"))
        assertEquals(BubbleForm.Form.Inline("민수님: 안녕 잘 지내?"), BubbleForm.of("민수", "안녕\r\n잘 지내?", m))
    }

    @Test fun longMessageBubbleLeaksNoBodyCharacter() {
        val out = BubbleForm.of("민수", "비밀번호는 " + "가".repeat(60), m)
        assertEquals("✉️ 민수님 메시지 도착!", out.text)
        assertTrue("비밀" !in out.text)
    }
}
