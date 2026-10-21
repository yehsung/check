// 원본: Sources/check/CheckWindowAnchor.swift 머리 @ a63fea2 (맥: 위 모서리 고정, 아래로 자람 — Windows 는 작업 표시줄 쪽 고정으로 뒤집는다)
//       · 시험은 새 코드: 설계 D§3-3(높이 = min(내용, 700 DIP, 영역 − 24 DIP), 12 DIP 여백, 표 시험 축) · G §2-3 W1-f ②
//       · R2 검증 지적(M1b: 700 DIP 상한을 빼도 초록 / M2·M3: TOP·RIGHT 아이콘 비켜서기 분기가 안 재졌다)
package com.yehsung.aingcheck.desktop.platform.windows.flyout

import com.yehsung.aingcheck.desktop.platform.windows.support.Goldens
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * G §2-3 W1-f ②: 플라이아웃 배치 순수 함수 표 — 배율 6 × 가장자리 4 × 자동 숨김 2 × 음수 좌표 2 × 내용 2 = 192 경우.
 * 내용 축은 560 DIP(상한 아래)와 900 DIP(700 DIP 상한에 걸림 — 이 모니터의 영역 − 24 = 792 DIP 라 700 쪽이 먼저 문다)다.
 * 판정은 둘이다:
 *  - **성질**(독립 신탁): 영역 안·작업 표시줄과 안 겹침·고정 모서리가 작업 표시줄 쪽 여백 자리·크기·자라는 방향·
 *    음수 좌표 모니터는 같은 배치를 평행 이동한 것(주 모니터 결과와 비교 — 기준선이 다른 입력이다).
 *  - **골든**(변화 감지): 192 줄 표를 파일과 바이트로 대조한다. 성질이 못 보는 1px 변화도 잡는다.
 * 손계산 정답 몇 개는 따로 둔다(골든이 처음부터 틀렸을 가능성을 막는다).
 */
class FlyoutPlacementTableTest {
    private val scales = listOf(100, 125, 150, 175, 200, 250)

    data class Case(val scalePct: Int, val edge: TaskbarEdge, val autoHide: Boolean, val negative: Boolean, val contentDip: Double = 560.0)

    /** D§3-3 의 높이 상한(설계 글자 그대로 — 구현 상수에서 가져오지 않는다). */
    private val specMaxHeightDip = 700.0

    /** 1536×864 DIP 모니터(1920×1080 @125% 와 같은 논리 크기), 작업 표시줄 48 DIP. 음수 쪽은 주 모니터 왼쪽 위 대각선. */
    private fun request(c: Case): Pair<FlyoutRequest, PxRect> {
        val s = c.scalePct / 100.0
        val w = ScreenSpace.dipToPx(1536.0, s)
        val h = ScreenSpace.dipToPx(864.0, s)
        val ox = if (c.negative) -w else 0
        val oy = if (c.negative) -h else 0
        val monitor = PxRect(ox, oy, ox + w, oy + h)
        val tb = ScreenSpace.dipToPx(48.0, s)
        val band = when (c.edge) {
            TaskbarEdge.BOTTOM -> PxRect(ox, oy + h - tb, ox + w, oy + h)
            TaskbarEdge.TOP -> PxRect(ox, oy, ox + w, oy + tb)
            TaskbarEdge.LEFT -> PxRect(ox, oy, ox + tb, oy + h)
            TaskbarEdge.RIGHT -> PxRect(ox + w - tb, oy, ox + w, oy + h)
        }
        val work = if (c.autoHide) monitor else when (c.edge) {
            TaskbarEdge.BOTTOM -> monitor.copy(bottom = band.top)
            TaskbarEdge.TOP -> monitor.copy(top = band.bottom)
            TaskbarEdge.LEFT -> monitor.copy(left = band.right)
            TaskbarEdge.RIGHT -> monitor.copy(right = band.left)
        }
        val anchor = when (c.edge) {
            TaskbarEdge.BOTTOM, TaskbarEdge.TOP -> PxPoint(ox + w - ScreenSpace.dipToPx(120.0, s), Math.floorDiv(band.top + band.bottom, 2))
            TaskbarEdge.LEFT, TaskbarEdge.RIGHT -> PxPoint(Math.floorDiv(band.left + band.right, 2), oy + h - ScreenSpace.dipToPx(60.0, s))
        }
        val half = ScreenSpace.dipToPx(12.0, s)
        val icon = PxRect(anchor.x - half, anchor.y - half, anchor.x + half, anchor.y + half)
        return FlyoutRequest(anchor, icon, monitor, work, TaskbarInfo(c.edge, band, c.autoHide), s, c.contentDip) to band
    }

    private fun cases(): List<Case> = buildList {
        for (s in scales) for (e in TaskbarEdge.entries) for (a in listOf(false, true)) for (n in listOf(false, true)) {
            for (content in listOf(560.0, 900.0)) add(Case(s, e, a, n, content))
        }
    }

    @Test
    fun tableHas192CasesAndHalfOfThemExceedTheCap() {
        assertEquals(192, cases().size)
        assertEquals(96, cases().count { it.contentDip > specMaxHeightDip })
    }

    @Test
    fun everyCaseSatisfiesThePlacementProperties() {
        for (c in cases()) {
            val (req, band) = request(c)
            val p = FlyoutPlacer.place(req)
            val r = p.rect
            val m = ScreenSpace.dipToPx(FlyoutPlacer.MARGIN_DIP, req.scale)
            val bounds = FlyoutPlacer.usableArea(req).inset(m)
            assertTrue(bounds.contains(r), "$c: $r 가 영역 $bounds 밖")
            assertFalse(r.intersects(band), "$c: 작업 표시줄 $band 을 덮는다")
            assertFalse(r.intersects(req.iconRect!!), "$c: 아이콘을 덮는다")
            assertFalse(p.overlapsIcon, "$c")
            assertEquals(ScreenSpace.dipToPx(414.0, req.scale), r.width, "$c 폭")
            // 높이: 560 은 그대로, 900 은 700 DIP 상한에 걸린다(영역 − 24 = 792 DIP 는 더 넉넉하다).
            val expectedDip = if (c.contentDip > specMaxHeightDip) specMaxHeightDip else c.contentDip
            assertEquals(expectedDip, p.heightDip, "$c 높이(DIP)")
            assertEquals(ScreenSpace.dipToPx(expectedDip, req.scale), r.height, "$c 높이(px)")
            // 고정 모서리 = 작업 표시줄 쪽, 작업 표시줄에서 여백만큼 떨어진 자리.
            when (c.edge) {
                TaskbarEdge.BOTTOM -> assertEquals(band.top - m, r.bottom, "$c")
                TaskbarEdge.TOP -> assertEquals(band.bottom + m, r.top, "$c")
                TaskbarEdge.LEFT -> assertEquals(band.right + m, r.left, "$c")
                TaskbarEdge.RIGHT -> assertEquals(band.left - m, r.right, "$c")
            }
            // 기준점 정렬: 가로 작업 표시줄은 가운데 정렬 뒤 영역 안으로 민 값, 세로는 기준점 위로 자란 값.
            when (c.edge) {
                TaskbarEdge.BOTTOM, TaskbarEdge.TOP ->
                    assertEquals((req.anchor.x - r.width / 2).coerceIn(bounds.left, bounds.right - r.width), r.left, "$c 가로")
                TaskbarEdge.LEFT, TaskbarEdge.RIGHT ->
                    assertEquals((req.anchor.y - r.height).coerceIn(bounds.top, bounds.bottom - r.height), r.top, "$c 세로")
            }
        }
    }

    @Test
    fun growsAwayFromTheTaskbarWithAnchoredEdgeFixed() {
        for (c in cases().filter { it.contentDip == 560.0 }) {
            val small = FlyoutPlacer.place(request(c.copy(contentDip = 300.0)).first).rect
            val big = FlyoutPlacer.place(request(c).first).rect
            // 상한에 걸린 내용(900 → 700 DIP)도 같은 모서리를 지키고 더 자란다.
            val capped = FlyoutPlacer.place(request(c.copy(contentDip = 900.0)).first).rect
            when (c.edge) {
                TaskbarEdge.BOTTOM -> for ((a, b) in listOf(small to big, big to capped)) {
                    assertEquals(a.bottom, b.bottom, "$c"); assertTrue(b.top < a.top, "$c")
                }
                TaskbarEdge.TOP -> for ((a, b) in listOf(small to big, big to capped)) {
                    assertEquals(a.top, b.top, "$c"); assertTrue(b.bottom > a.bottom, "$c")
                }
                // 세로 작업 표시줄: 알림 영역이 아래 끝이라 기준점 위로 자란다(아래 모서리 고정).
                TaskbarEdge.LEFT, TaskbarEdge.RIGHT -> for ((a, b) in listOf(small to big, big to capped)) {
                    assertEquals(a.bottom, b.bottom, "$c"); assertTrue(b.top < a.top, "$c")
                }
            }
        }
    }

    @Test
    fun negativeCoordinateMonitorIsAPureTranslation() {
        for (c in cases().filter { !it.negative }) {
            val pos = FlyoutPlacer.place(request(c).first)
            val (negReq, _) = request(c.copy(negative = true))
            val neg = FlyoutPlacer.place(negReq)
            val dx = negReq.monitor.left
            val dy = negReq.monitor.top
            assertTrue(dx < 0 && dy < 0)
            assertEquals(pos.rect.translate(dx, dy), neg.rect, "$c")
            assertTrue(neg.rect.left < 0 && neg.rect.top < 0, "$c 음수 좌표가 아니다")
        }
    }

    @Test
    fun handComputedFullHd100PercentBottomTaskbar() {
        val req = FlyoutRequest(
            anchor = PxPoint(1800, 1056),
            iconRect = PxRect(1788, 1044, 1812, 1068),
            monitor = PxRect(0, 0, 1920, 1080),
            workArea = PxRect(0, 0, 1920, 1032),
            taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 1032, 1920, 1080), autoHide = false),
            scale = 1.0,
            contentHeightDip = 560.0,
        )
        // 여백 12 → 영역 (12,12,1908,1020). 가로 1800−207=1593 → 오른쪽 한계 1908−414=1494 로 밀림.
        assertEquals(PxRect(1494, 460, 1908, 1020), FlyoutPlacer.place(req).rect)
    }

    @Test
    fun fullHd100PercentCapsTallContentAt700Dip() {
        // 1920×1080 @100%, 아래 작업 표시줄 48px → 작업 영역 높이 1032. 내용 900 DIP.
        val req = FlyoutRequest(
            anchor = PxPoint(1800, 1056),
            iconRect = PxRect(1788, 1044, 1812, 1068),
            monitor = PxRect(0, 0, 1920, 1080),
            workArea = PxRect(0, 0, 1920, 1032),
            taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 1032, 1920, 1080), autoHide = false),
            scale = 1.0,
            contentHeightDip = 900.0,
        )
        val p = FlyoutPlacer.place(req)
        // 상한 = min(700, 1032 − 24 = 1008) = 700 DIP — 이 화면에서는 영역이 아니라 700 쪽이 문다.
        assertEquals(700.0, p.maxHeightDip)
        assertEquals(700.0, p.heightDip)
        // 여백 12 → 아래 모서리 1032 − 12 = 1020 고정, 위로 700px → 320. 가로는 1908 − 414 = 1494 로 밀림.
        assertEquals(PxRect(1494, 320, 1908, 1020), p.rect)
        assertEquals(700, p.rect.height)
        assertFalse(p.overlapsIcon)
    }

    @Test
    fun laptop1366x768CapsHeightBelow700() {
        val req = FlyoutRequest(
            anchor = PxPoint(1300, 744),
            iconRect = null,
            monitor = PxRect(0, 0, 1366, 768),
            workArea = PxRect(0, 0, 1366, 720),
            taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 720, 1366, 768), autoHide = false),
            scale = 1.0,
            contentHeightDip = 900.0,
        )
        val p = FlyoutPlacer.place(req)
        // 상한 = min(700, 720 − 24) = 696 DIP. 여백 안 영역 높이도 720 − 24 = 696 이라 꼭 맞는다.
        assertEquals(696.0, p.maxHeightDip)
        assertEquals(696.0, p.heightDip)
        assertEquals(PxRect(1366 - 12 - 414, 12, 1366 - 12, 708), p.rect)
    }

    @Test
    fun hiddenAutoHideTaskbarReportedThinUsesDefaultBand() {
        val req = FlyoutRequest(
            anchor = PxPoint(1800, 1079),
            iconRect = null,
            monitor = PxRect(0, 0, 1920, 1080),
            workArea = PxRect(0, 0, 1920, 1080),
            taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 1078, 1920, 1080), autoHide = true),
            scale = 1.5,
            contentHeightDip = 400.0,
        )
        // 2px 로 보고되면(숨은 상태) 48 DIP × 1.5 = 72px 띠를 뺀다 → 아래 모서리 = 1080 − 72 − 18.
        assertEquals(1080 - 72 - 18, FlyoutPlacer.place(req).rect.bottom)
    }

    /**
     * 넘침 영역(작업 영역 **안**)의 아이콘을 덮으면 작업 표시줄 반대쪽으로 비켜선다 — 가장자리 넷 각각 손계산.
     * 모두 1920×1080 @100%, 작업 표시줄 48px, 내용 560 DIP, 아이콘 32px, 기준점 = 아이콘 가운데(NIN_SELECT 좌표).
     */
    @Test
    fun overflowIconInsideWorkAreaIsAvoidedOnEveryEdge() {
        fun req(edge: TaskbarEdge, band: PxRect, work: PxRect, icon: PxRect) = FlyoutRequest(
            anchor = PxPoint((icon.left + icon.right) / 2, (icon.top + icon.bottom) / 2),
            iconRect = icon,
            monitor = PxRect(0, 0, 1920, 1080),
            workArea = work,
            taskbar = TaskbarInfo(edge, band, autoHide = false),
            scale = 1.0,
            contentHeightDip = 560.0,
        )

        // BOTTOM: 여백 안 영역 (12,12,1908,1020). 기본 자리 (1494,460,1908,1020) 가 아이콘 (1700,900,1732,932) 을 덮는다
        // → 아이콘 위로: 아래 = 900 − 12 = 888, 위 = 888 − 560 = 328.
        val bottom = FlyoutPlacer.place(req(TaskbarEdge.BOTTOM, PxRect(0, 1032, 1920, 1080), PxRect(0, 0, 1920, 1032), PxRect(1700, 900, 1732, 932)))
        assertEquals(PxRect(1494, 328, 1908, 888), bottom.rect)
        assertFalse(bottom.overlapsIcon)

        // TOP: 영역 (0,48,1920,1080) → 여백 안 (12,60,1908,1068). 기본 자리 (1494,60,1908,620) 가 아이콘 (1700,148,1732,180) 을 덮는다
        // → 아이콘 아래로: 위 = 180 + 12 = 192, 아래 = 192 + 560 = 752.
        val top = FlyoutPlacer.place(req(TaskbarEdge.TOP, PxRect(0, 0, 1920, 48), PxRect(0, 48, 1920, 1080), PxRect(1700, 148, 1732, 180)))
        assertEquals(PxRect(1494, 192, 1908, 752), top.rect)
        assertFalse(top.overlapsIcon)

        // LEFT: 영역 (48,0,1920,1080) → 여백 안 (60,12,1908,1068). 기본 자리 = 왼쪽 60 고정, 기준점 916 위로 560 → (60,356,474,916),
        // 아이콘 (100,900,132,932) 을 덮는다 → 아이콘 오른쪽으로: 왼 = 132 + 12 = 144, 오른 = 144 + 414 = 558.
        val left = FlyoutPlacer.place(req(TaskbarEdge.LEFT, PxRect(0, 0, 48, 1080), PxRect(48, 0, 1920, 1080), PxRect(100, 900, 132, 932)))
        assertEquals(PxRect(144, 356, 558, 916), left.rect)
        assertFalse(left.overlapsIcon)

        // RIGHT: 영역 (0,0,1872,1080) → 여백 안 (12,12,1860,1068). 기본 자리 = 오른쪽 1860 고정 → (1446,356,1860,916),
        // 아이콘 (1788,900,1820,932) 을 덮는다 → 아이콘 왼쪽으로: 오른 = 1788 − 12 = 1776, 왼 = 1776 − 414 = 1362.
        val right = FlyoutPlacer.place(req(TaskbarEdge.RIGHT, PxRect(1872, 0, 1920, 1080), PxRect(0, 0, 1872, 1080), PxRect(1788, 900, 1820, 932)))
        assertEquals(PxRect(1362, 356, 1776, 916), right.rect)
        assertFalse(right.overlapsIcon)
    }

    @Test
    fun crampedOverflowIconIsReportedInsteadOfMovedSomewhereOdd() {
        // 자리가 모자라면 겹친 채 알린다(조용히 엉뚱한 곳으로 가지 않는다). 아이콘 위로 비켜서면 위 = 400 − 12 − 700 < 12.
        val p = FlyoutPlacer.place(
            FlyoutRequest(
                anchor = PxPoint(1716, 416),
                iconRect = PxRect(1700, 400, 1732, 432),
                monitor = PxRect(0, 0, 1920, 1080),
                workArea = PxRect(0, 0, 1920, 1032),
                taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 1032, 1920, 1080), autoHide = false),
                scale = 1.0,
                contentHeightDip = 900.0,
            ),
        )
        assertTrue(p.overlapsIcon)
        assertEquals(PxRect(1494, 320, 1908, 1020), p.rect, "자리가 없으면 기본 자리에 남는다")
    }

    @Test
    fun goldenTableIsUnchanged() {
        val text = buildString {
            append("# 플라이아웃 배치 표 — FlyoutPlacementTableTest 가 만든다. 배율% 가장자리 자동숨김 음수좌표 내용DIP → l t r b 높이DIP 상한DIP 겹침\n")
            for (c in cases()) {
                val p = FlyoutPlacer.place(request(c).first)
                val r = p.rect
                append("${c.scalePct} ${c.edge} ${if (c.autoHide) "autohide" else "fixed"} ${if (c.negative) "neg" else "pos"} ${c.contentDip} -> ")
                append("${r.left} ${r.top} ${r.right} ${r.bottom} ${p.heightDip} ${p.maxHeightDip} ${p.overlapsIcon}\n")
            }
        }
        Goldens.assertText("flyout/flyout-placement.golden.txt", text)
    }
}
