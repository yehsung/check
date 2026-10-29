// 원본: CheckOverlayWindow.swift :2011-2100 saveOffset/loadOffset(check.overlayOffset — 깨진 값은 기본 자리로)
package com.yehsung.aingcheck.desktop.overlay.surface

import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPlacement
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class OverlayPlacementStoreTest {
    @Test
    fun roundTripsMonitorKeyAndOffsets() {
        val kv = InMemoryDesktopKeyValueStore()
        val store = OverlayPlacementStore(kv)
        assertNull(store.load())
        val p = OverlayPlacement("\\\\.\\DISPLAY2", 24.0, 37.5)
        store.save(p)
        assertEquals(p, store.load())
        assertEquals("\\\\.\\DISPLAY2\t24.0\t37.5", kv.getString(OverlayPlacementStore.KEY))
        store.save(null)
        assertNull(store.load())
    }

    @Test
    fun brokenValuesReadAsNothing() {
        for (raw in listOf("", "\\\\.\\DISPLAY1", "\\\\.\\DISPLAY1\t1", "\t1\t2", "D\tx\t2", "D\t1\tNaN", "D\t1\t2\t3")) {
            assertNull(OverlayPlacementStore(InMemoryDesktopKeyValueStore(mapOf(OverlayPlacementStore.KEY to raw))).load(), "'$raw'")
        }
        val kv = InMemoryDesktopKeyValueStore()
        OverlayPlacementStore(kv).save(OverlayPlacement("a\tb", 1.0, 2.0))
        assertNull(kv.getString(OverlayPlacementStore.KEY), "탭이 든 키는 저장하지 않는다")
    }
}
