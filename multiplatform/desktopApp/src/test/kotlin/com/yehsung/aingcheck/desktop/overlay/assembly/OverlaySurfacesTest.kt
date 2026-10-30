// 원본: CheckOverlayWindow.swift :2009-2036 reposition · :2185-2196 overlayFrame(offset:) · :1702-1706 ultraPanelFrame · :1938 복원 · :817-822 울트라 클릭 통과
// 가짜 표면(창 0) — FrameIntent 순서·좌표가 OverlayGeometry 대로 픽셀이 되는지, 숨김·그리기 정지·끌기, Windows 밖은 화면 없음.
package com.yehsung.aingcheck.desktop.overlay.assembly

import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.FrameIntent
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.MonitorInfo
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayGeometry
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayInputs
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPlacement
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.engine.Fixture
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.surface.OverlaySurfaceListener
import com.yehsung.aingcheck.desktop.wiring.OverlayPresenter
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class OverlaySurfacesTest {
    private val primary = MonitorInfo("\\\\.\\DISPLAY1", OverlayRect(0.0, 0.0, 1280.0, 720.0), OverlayRect(0.0, 0.0, 1280.0, 690.0), primary = true)
    private val second = MonitorInfo("\\\\.\\DISPLAY2", OverlayRect(1280.0, 0.0, 1920.0, 1080.0), OverlayRect(1280.0, 0.0, 1920.0, 1040.0))

    class FakePort(var monitorList: List<MonitorInfo>, var scale: Double) : OverlaySurfacePort {
        val log = ArrayList<String>()
        var monitorReads = 0
        override fun monitors(): List<MonitorInfo> { monitorReads += 1; return monitorList }
        override fun dpiScale(): Double = scale
        override fun present(frame: ComposedOverlay, xPx: Int, yPx: Int): Boolean { log += "present $xPx,$yPx ${frame.width}x${frame.height}"; return true }
        override fun moveTo(xPx: Int, yPx: Int) { log += "move $xPx,$yPx" }
        override fun hide() { log += "hide" }
        override fun setClickThrough(enabled: Boolean) { log += "through $enabled" }
    }

    private var composes = 0
    private val composer = OverlayFrameComposer { _, w, h, _, _ -> composes += 1; ComposedOverlay.empty(w, h) }

    private fun view(frame: FrameIntent, mode: OverlayMode = OverlayMode.Normal, suspended: Boolean = false) = OverlayView(
        mode = mode, characterId = "aing", bubble = null, activeReaction = null, reactionStartedAt = null, sleeping = false,
        facing = 0, walking = false, particles = emptyList(), frame = frame, renderSuspended = suspended,
    )

    @Test
    fun defaultIntentPutsThePanelTopRightOfThePrimaryWorkAreaInWindowPixels() {
        val port = FakePort(listOf(primary, second), scale = 1.5)
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.present(view(FrameIntent.Default(0)), 0.0)
        // 맥 overlayFrame: visibleFrame 오른쪽 위에서 24 안쪽, 140×170 — Windows 는 위가 top.
        val expected = OverlayGeometry.defaultFrame(primary.work)
        assertEquals(OverlayRect(1280.0 - 140 - 24, 24.0, 140.0, 170.0), expected)
        assertEquals(expected, p.frameDip)
        assertEquals(listOf("present 1674,36 210x255"), port.log)
    }

    @Test
    fun savedPlacementOnTheSecondMonitorIsRestoredFromItsTopRightOffset() {
        val port = FakePort(listOf(primary, second), scale = 1.0)
        val p = OverlaySurfacePresenter(port, composer) { OverlayPlacement(second.key, rx = 100.0, ry = 50.0) }
        p.present(view(FrameIntent.Default(0)), 0.0)
        assertEquals(OverlayRect(3200.0 - 100 - 140, 50.0, 140.0, 170.0), p.frameDip)
        assertEquals(listOf("present 2960,50 140x170"), port.log)
    }

    @Test
    fun intentsApplyOncePerSeqInOrder_ultraCoversTheScreenBandClickThroughThenRestores() {
        val port = FakePort(listOf(primary, second), scale = 1.5)
        val p = OverlaySurfacePresenter(port, composer) { null }
        val start = OverlayGeometry.defaultFrame(primary.work)
        p.present(view(FrameIntent.Default(0)), 0.0)
        p.present(view(FrameIntent.Default(0)), 0.033) // 같은 seq — 모니터를 다시 읽지 않는다
        assertEquals(1, port.monitorReads)

        p.present(view(FrameIntent.UltraCover(1), OverlayMode.Ultra), 0.066)
        val band = OverlayFramePlacement.ultraFrame(primary.bounds)
        // 화면 높이 전체 · 140:170 · 가운데.
        assertEquals(720.0, band.height)
        assertEquals(720.0 * 140 / 170, band.width, 1e-9)
        assertEquals((1280.0 - band.width) / 2, band.left, 1e-9)
        assertEquals(band, p.frameDip)
        assertTrue(p.clickThrough)

        p.present(view(FrameIntent.Restore(start, 2)), 5.1)
        assertEquals(start, p.frameDip)
        assertFalse(p.clickThrough)
        assertEquals(3, port.monitorReads)
        val bandPx = OverlayFramePlacement.toPx(band, 1.5)
        assertEquals(
            listOf(
                "present 1674,36 210x255", "present 1674,36 210x255",
                "through true", "present ${bandPx.x},${bandPx.y} ${bandPx.width}x${bandPx.height}",
                "through false", "present 1674,36 210x255",
            ),
            port.log,
        )
        assertEquals(PxBox(515, 0, 890, 1080), bandPx)
    }

    /** int-w4b ① — 엿보기·작별 인사는 창 전체 클릭 통과(맥 :729 updateHitThrough 의 shouldBeVisible 가드), 근무 중 표시는 다시 클릭을 받는다. 숨김은 토글 없음. */
    @Test
    fun peekAndFarewellAreClickThroughLikeMac_normalTakesClicksAgain() {
        val port = FakePort(listOf(primary), scale = 1.0)
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.present(view(FrameIntent.Default(0), OverlayMode.Peek), 0.0)
        assertTrue(p.clickThrough, "엿보기")
        p.present(view(FrameIntent.Default(1), OverlayMode.Normal), 0.1)
        assertFalse(p.clickThrough, "근무 중")
        p.present(view(FrameIntent.Default(1), OverlayMode.Farewell), 0.2)
        assertTrue(p.clickThrough, "작별 인사")
        p.present(view(FrameIntent.Default(1), OverlayMode.Hidden), 0.3)
        assertEquals(listOf("through true", "through false", "through true"), port.log.filter { it.startsWith("through") })
        assertEquals("through true", port.log.first(), "통과는 그리기보다 먼저")
    }

    @Test
    fun ultraPicksTheMonitorUnderThePanelCenter() {
        val port = FakePort(listOf(primary, second), scale = 1.0)
        val p = OverlaySurfacePresenter(port, composer) { OverlayPlacement(second.key, 100.0, 50.0) }
        p.present(view(FrameIntent.Default(0)), 0.0)
        p.present(view(FrameIntent.UltraCover(1), OverlayMode.Ultra), 0.1)
        assertEquals(OverlayFramePlacement.ultraFrame(second.bounds), p.frameDip)
        assertTrue(p.frameDip!!.left >= second.bounds.left, "둘째 모니터를 덮어야 한다")
    }

    @Test
    fun hiddenHidesOnceWithoutComposing_suspendedKeepsTheLastPicture_intentStillApplies() {
        val port = FakePort(listOf(primary), scale = 1.0)
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.present(view(FrameIntent.Default(0)), 0.0)
        assertEquals(1, composes)
        p.present(view(FrameIntent.Default(0), OverlayMode.Hidden), 0.1)
        p.present(view(FrameIntent.Default(0), OverlayMode.Hidden), 0.2)
        assertEquals(listOf("present 1116,24 140x170", "hide"), port.log)
        assertEquals(1, composes, "숨김은 합성하지 않는다")
        // 그리기 정지 중 새 지시: 자리는 바꾸되 그리지 않는다.
        p.present(view(FrameIntent.Restore(OverlayRect(10.0, 20.0, 140.0, 170.0), 1), suspended = true), 0.3)
        assertEquals(OverlayRect(10.0, 20.0, 140.0, 170.0), p.frameDip)
        assertEquals(1, composes, "그리기 정지는 합성하지 않는다")
        p.present(view(FrameIntent.Restore(OverlayRect(10.0, 20.0, 140.0, 170.0), 1)), 0.4)
        assertEquals("present 10,20 140x170", port.log.last())
    }

    @Test
    fun dragMoveToMovesTheWindowInPixelsWithoutRecomposing() {
        val port = FakePort(listOf(primary), scale = 1.25)
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.present(view(FrameIntent.Default(0)), 0.0)
        p.onPointerOutcome(PointerOutcome(moveTo = OverlayPoint(400.0, 300.0)))
        p.onPointerOutcome(PointerOutcome()) // 이동 없음 — 아무것도 안 한다
        assertEquals("move 500,375", port.log.last())
        assertEquals(2, port.log.size)
        assertEquals(OverlayRect(400.0, 300.0, 140.0, 170.0), p.frameDip)
    }

    @Test
    fun bindFeedsTheEngineMonitorsAndSurfaceFrame_andTheEngineDragUsesThem() {
        val f = Fixture()
        val frames = ArrayList<OverlayRect>()
        val monitorsSeen = ArrayList<List<MonitorInfo>>()
        val rec = object : OverlayInputs by f.d {
            override fun onMonitors(monitors: List<MonitorInfo>) { monitorsSeen += monitors; f.d.onMonitors(monitors) }
            override fun onSurfaceFrame(frame: OverlayRect) { frames += frame; f.d.onSurfaceFrame(frame) }
        }
        val port = FakePort(listOf(primary, second), scale = 1.0)
        val p = OverlaySurfacePresenter(port, composer) { null }
        p.bind(rec)
        val now = f.working()
        p.present(f.d.view(now), now)
        assertEquals(listOf(listOf(primary, second)), monitorsSeen)
        assertEquals(listOf(OverlayGeometry.defaultFrame(primary.work)), frames)
        // 엔진 끌기: 되먹인 프레임에서 시작해 조인 왼쪽 위를 낸다 → 발표자가 창을 옮긴다.
        val start = frames.single()
        val at = OverlayPoint(start.left + 70, start.top + 85)
        f.d.onPointer(PointerKind.DOWN, at, HitTarget.Body, now)
        val out = f.d.onPointer(PointerKind.DRAG, OverlayPoint(at.x - 300, at.y + 200), HitTarget.Body, now + 0.1)
        assertEquals(OverlayPoint(start.left - 300, start.top + 200), out.moveTo)
        p.onPointerOutcome(out)
        assertEquals("move ${(start.left - 300).toInt()},${(start.top + 200).toInt()}", port.log.last())
    }

    @Test
    fun toPxRoundsEdgesSoNeighboursDoNotGap() {
        assertEquals(PxBox(1, 1, 175, 213), OverlayFramePlacement.toPx(OverlayRect(1.0, 1.0, 140.0, 170.0), 1.25))
        assertEquals(PxBox(0, 0, 1, 1), OverlayFramePlacement.toPx(OverlayRect(0.0, 0.0, 0.1, 0.1), 1.0))
    }

    // ───────────────────────── 음성: Windows 밖은 화면 없음 ─────────────────────────

    private val kv = object : DesktopKeyValueStore {
        val m = HashMap<String, String>()
        override fun getString(key: String): String? = m[key]
        override fun putString(key: String, value: String?) { if (value == null) m.remove(key) else m[key] = value }
        override fun keys(prefix: String): List<String> = m.keys.filter { it.startsWith(prefix) }.sorted()
    }

    @Test
    fun outsideWindowsTheAssemblyIsNone_noWindowNoBoardSilentSink() {
        val s = OverlaySurfaces.create(platform = null, config = OverlaySurfacesConfig(kv), isWindows = false)
        assertFalse(s.isLive)
        assertSame(OverlayPresenter.None, s.presenter)
        assertSame(BoardHost.None, s.board)
        assertTrue(s.sink is SilentCharacterSink)
        assertNull(s.surfacePresenter)
        // bind·포인터 결과도 아무 일 없이 지난다.
        s.bind(Fixture().d, OverlaySurfaceListener { _, _, _ -> error("불리면 안 된다") })
        s.onPointerOutcome(PointerOutcome(moveTo = OverlayPoint(1.0, 1.0)))
        s.close()
        // isWindows=true 여도 메시지 스레드가 없으면(세션 0 등) 화면 없음.
        assertFalse(OverlaySurfaces.createOn(thread = null, config = OverlaySurfacesConfig(kv), isWindows = true).isLive)
        assertTrue(kv.m.isEmpty(), "화면 없음 조립은 저장소에 쓰지 않는다")
    }
}
