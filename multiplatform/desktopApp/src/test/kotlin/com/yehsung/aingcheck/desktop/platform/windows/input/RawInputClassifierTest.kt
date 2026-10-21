// 원본: Sources/check/CheckWorkNudge.swift:13-19, 72-77 @ a63fea2 (키·클릭·스크롤만 센다, 이동은 뺀다) — 시험은 새 코드:
//       설계 D§5-1(RAWINPUT 바이트 배치는 winuser.h 대로 손으로 짓는다)
package com.yehsung.aingcheck.desktop.platform.windows.input

import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.desktop.platform.windows.input.RawInputClassifier.RIM_TYPEHID
import com.yehsung.aingcheck.desktop.platform.windows.input.RawInputClassifier.RIM_TYPEKEYBOARD
import com.yehsung.aingcheck.desktop.platform.windows.input.RawInputClassifier.RIM_TYPEMOUSE
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

/**
 * 맥 계약(키·클릭·스크롤만, 이동 제외)을 RAWINPUT 바이트에서 잰다. 버퍼는 winuser.h 배치대로 손으로 짓는다 —
 * 분류기의 오프셋을 그대로 베끼면 둘이 같이 틀려도 초록이므로, 칸마다 다른 값(표식)을 넣어 엉뚱한 칸을 읽으면 빨갛게 한다.
 */
class RawInputClassifierTest {
    private fun header(bb: ByteBuffer, type: Int, size: Int, pointer: Int) {
        bb.putInt(0, type)
        bb.putInt(4, size)
        // hDevice·wParam 은 표식 값으로 채운다(분류기가 머리말을 데이터로 읽으면 판정이 바뀐다).
        if (pointer == 8) {
            bb.putLong(8, 0x0FFF_0FFF_0FFF_0FFFL)
            bb.putLong(16, 0x0FFF_0FFF_0FFF_0FFFL)
        } else {
            bb.putInt(8, 0x0FFF_0FFF)
            bb.putInt(12, 0x0FFF_0FFF)
        }
    }

    private fun keyboard(flags: Int, pointer: Int = 8): ByteArray {
        val h = 8 + 2 * pointer
        val bb = ByteBuffer.allocate(h + 16).order(ByteOrder.LITTLE_ENDIAN)
        header(bb, RIM_TYPEKEYBOARD, h + 16, pointer)
        bb.putShort(h + 0, 0x1E) // MakeCode('A')
        bb.putShort(h + 2, flags.toShort())
        bb.putShort(h + 4, 0x7FFF) // Reserved(표식)
        bb.putShort(h + 6, 0x41) // VKey
        bb.putInt(h + 8, 0x0100) // WM_KEYDOWN
        bb.putInt(h + 12, 0x7FFF_FFFF)
        return bb.array()
    }

    private fun mouse(usFlags: Int, buttonFlags: Int, dx: Int, dy: Int, pointer: Int = 8): ByteArray {
        val h = 8 + 2 * pointer
        val bb = ByteBuffer.allocate(h + 24).order(ByteOrder.LITTLE_ENDIAN)
        header(bb, RIM_TYPEMOUSE, h + 24, pointer)
        bb.putShort(h + 0, usFlags.toShort())
        bb.putShort(h + 2, 0x7FFF) // 맞춤 칸(표식) — 여기를 단추 깃발로 읽으면 엉뚱한 판정
        bb.putShort(h + 4, buttonFlags.toShort())
        bb.putShort(h + 6, 0x0078) // usButtonData(휠 120)
        bb.putInt(h + 8, 0x7FFF_FFFF) // ulRawButtons(표식)
        bb.putInt(h + 12, dx)
        bb.putInt(h + 16, dy)
        bb.putInt(h + 20, 0x7FFF_FFFF)
        return bb.array()
    }

    @Test
    fun keyboardMakeCountsBreakDoesNot() {
        for (p in listOf(8, 4)) {
            assertEquals(InputKind.KEY, RawInputClassifier.classify(keyboard(flags = 0, pointer = p), p), "make p=$p")
            assertEquals(InputKind.KEY, RawInputClassifier.classify(keyboard(flags = 2 /* RI_KEY_E0 */, pointer = p), p), "E0 make p=$p")
            assertNull(RawInputClassifier.classify(keyboard(flags = 1 /* RI_KEY_BREAK */, pointer = p), p), "break p=$p")
        }
    }

    @Test
    fun mouseButtonDownIsClickButUpIsNothing() {
        val downs = listOf(0x0001, 0x0004, 0x0010, 0x0040, 0x0100)
        for (p in listOf(8, 4)) {
            for (d in downs) assertEquals(InputKind.CLICK, RawInputClassifier.classify(mouse(0, d, 0, 0, p), p), "down 0x${d.toString(16)} p=$p")
            for (u in listOf(0x0002, 0x0008, 0x0020, 0x0080, 0x0200)) {
                assertNull(RawInputClassifier.classify(mouse(0, u, 0, 0, p), p), "up 0x${u.toString(16)} p=$p")
            }
        }
    }

    @Test
    fun wheelAndHorizontalWheelAreWheel() {
        assertEquals(InputKind.WHEEL, RawInputClassifier.classify(mouse(0, 0x0400, 0, 0), 8))
        assertEquals(InputKind.WHEEL, RawInputClassifier.classify(mouse(0, 0x0800, 0, 0), 8))
    }

    @Test
    fun movementAloneIsOnlyMove() {
        assertEquals(InputKind.MOVE, RawInputClassifier.classify(mouse(0, 0, 3, 0), 8))
        assertEquals(InputKind.MOVE, RawInputClassifier.classify(mouse(0, 0, 0, -1), 8))
        // 절대 좌표 장치(RDP·태블릿)는 좌표가 0 이어도 이동이다.
        assertEquals(InputKind.MOVE, RawInputClassifier.classify(mouse(0x0001, 0, 0, 0), 8))
        assertNull(RawInputClassifier.classify(mouse(0, 0, 0, 0), 8), "아무 일 없는 건")
    }

    @Test
    fun clickWinsOverWheelAndMoveInOnePacket() {
        assertEquals(InputKind.CLICK, RawInputClassifier.classify(mouse(0, 0x0001 or 0x0400, 5, 5), 8))
        assertEquals(InputKind.WHEEL, RawInputClassifier.classify(mouse(0, 0x0400 or 0x0002, 5, 5), 8))
    }

    @Test
    fun hidAndTruncatedBuffersAreIgnored() {
        val hid = keyboard(0).also { ByteBuffer.wrap(it).order(ByteOrder.LITTLE_ENDIAN).putInt(0, RIM_TYPEHID) }
        assertNull(RawInputClassifier.classify(hid, 8))
        assertNull(RawInputClassifier.classify(keyboard(0).copyOf(30), 8))
        assertNull(RawInputClassifier.classify(mouse(0, 1, 0, 0).copyOf(40), 8))
        assertNull(RawInputClassifier.classify(ByteArray(3), 8))
    }

    @Test
    fun lastInputTickConversionHandlesWraparound() {
        val now = Instant.fromEpochMilliseconds(1_800_000_000_000)
        assertEquals(now - 1_500.milliseconds, LastInputTicks.toInstant(now, tickNow = 10_000, lastInputTick = 8_500))
        // GetTickCount 는 49.7일마다 0 으로 감긴다: 지금 틱 100, 마지막 입력 0xFFFFFF00 → 356ms 전.
        assertEquals(now - 356.milliseconds, LastInputTicks.toInstant(now, tickNow = 100, lastInputTick = 0xFFFF_FF00L))
        // JNA 는 DWORD 를 부호 있는 int 로 준다 — 음수로 들어와도 같은 답.
        assertEquals(now - 356.milliseconds, LastInputTicks.toInstant(now, tickNow = 100, lastInputTick = (-256).toLong()))
    }
}
