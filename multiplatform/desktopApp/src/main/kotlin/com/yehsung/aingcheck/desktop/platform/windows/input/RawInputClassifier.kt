// 원본: Sources/check/CheckWorkNudge.swift:13-19, 72-77 @ a63fea2 (키·클릭·스크롤만 센다, 마우스 이동은 뺀다)
//       · 설계 D§5-1(Raw Input: 키 누름·단추 누름·휠만 **시각**으로, 키 값·좌표는 읽지도 저장하지도 않는다)
//
// WM_INPUT 의 RAWINPUT 버퍼 한 건 → 입력 종류(순수 함수). 맥과 의미를 맞춘다:
//  - 키보드: 누름(make)만. 뗌(RI_KEY_BREAK)은 세지 않는다(맥 .keyDown).
//  - 마우스: 단추 **누름** 비트(좌·우·가운데·4·5)는 CLICK, 휠·가로 휠은 WHEEL, 나머지 움직임은 MOVE(자리 비움 판정에서 뺀다).
//    한 건에 누름과 휠이 같이 오면 CLICK 이 이긴다. 단추 뗌만 있는 건은 null(맥도 mouseUp 을 보지 않는다).
// 키 값(VKey·MakeCode)과 좌표(lLastX·lLastY)는 **판정 안에서만** 읽고 어디에도 남기지 않는다 — 좌표는 0 인지(움직임이 있었는지)만 본다.
//
// 버퍼 배치(winuser.h, 리틀 엔디언):
//   RAWINPUTHEADER  dwType(4) dwSize(4) hDevice(포인터) wParam(포인터)       = 8 + 2·포인터
//   RAWMOUSE        usFlags(2) pad(2) usButtonFlags(2) usButtonData(2) ulRawButtons(4) lLastX(4) lLastY(4) ulExtraInformation(4)
//   RAWKEYBOARD     MakeCode(2) Flags(2) Reserved(2) VKey(2) Message(4) ExtraInformation(4)
package com.yehsung.aingcheck.desktop.platform.windows.input

import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import java.nio.ByteBuffer
import java.nio.ByteOrder

object RawInputClassifier {
    const val RIM_TYPEMOUSE = 0
    const val RIM_TYPEKEYBOARD = 1
    const val RIM_TYPEHID = 2

    const val RI_KEY_BREAK = 0x0001

    const val RI_MOUSE_LEFT_BUTTON_DOWN = 0x0001
    const val RI_MOUSE_LEFT_BUTTON_UP = 0x0002
    const val RI_MOUSE_RIGHT_BUTTON_DOWN = 0x0004
    const val RI_MOUSE_RIGHT_BUTTON_UP = 0x0008
    const val RI_MOUSE_MIDDLE_BUTTON_DOWN = 0x0010
    const val RI_MOUSE_MIDDLE_BUTTON_UP = 0x0020
    const val RI_MOUSE_BUTTON_4_DOWN = 0x0040
    const val RI_MOUSE_BUTTON_4_UP = 0x0080
    const val RI_MOUSE_BUTTON_5_DOWN = 0x0100
    const val RI_MOUSE_BUTTON_5_UP = 0x0200
    const val RI_MOUSE_WHEEL = 0x0400
    const val RI_MOUSE_HWHEEL = 0x0800

    const val MOUSE_MOVE_ABSOLUTE = 0x0001

    private const val DOWN_BITS = RI_MOUSE_LEFT_BUTTON_DOWN or RI_MOUSE_RIGHT_BUTTON_DOWN or RI_MOUSE_MIDDLE_BUTTON_DOWN or
        RI_MOUSE_BUTTON_4_DOWN or RI_MOUSE_BUTTON_5_DOWN
    private const val WHEEL_BITS = RI_MOUSE_WHEEL or RI_MOUSE_HWHEEL

    fun classifyKeyboard(flags: Int): InputKind? = if (flags and RI_KEY_BREAK == 0) InputKind.KEY else null

    fun classifyMouse(usFlags: Int, buttonFlags: Int, lastX: Int, lastY: Int): InputKind? = when {
        buttonFlags and DOWN_BITS != 0 -> InputKind.CLICK
        buttonFlags and WHEEL_BITS != 0 -> InputKind.WHEEL
        lastX != 0 || lastY != 0 || (usFlags and MOUSE_MOVE_ABSOLUTE) != 0 -> InputKind.MOVE
        else -> null
    }

    /** GetRawInputData(RID_INPUT) 가 채운 버퍼 전체. [pointerSize] 는 프로세스의 포인터 크기(64비트 8). 모자라거나 HID 면 null. */
    fun classify(buffer: ByteArray, pointerSize: Int): InputKind? {
        val header = 8 + 2 * pointerSize
        if (buffer.size < header) return null
        val bb = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN)
        return when (bb.getInt(0)) {
            RIM_TYPEKEYBOARD -> {
                if (buffer.size < header + 16) return null
                classifyKeyboard(bb.getShort(header + 2).toInt() and 0xFFFF)
            }
            RIM_TYPEMOUSE -> {
                if (buffer.size < header + 24) return null
                classifyMouse(
                    usFlags = bb.getShort(header).toInt() and 0xFFFF,
                    buttonFlags = bb.getShort(header + 4).toInt() and 0xFFFF,
                    lastX = bb.getInt(header + 12),
                    lastY = bb.getInt(header + 16),
                )
            }
            else -> null
        }
    }
}
