// 원본: Sources/check/CheckTodoBoardWindow.swift:25-67(TodoBoardAnchor) · Sources/check/CheckApp.swift:557-561(BoardFacing) @ ef9fab11
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.desktop.overlay.engine.OverlayGeometry
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect

/**
 * 캐릭터(앵커) 옆에 보드를 놓는 규칙 — 화면·창에 손대지 않는 **값 계산만**(맥 TodoBoardAnchor).
 *
 * 좌표는 DIP·**y 아래로**(Windows 관례, overlay 계약과 같다). 맥은 y 위로라 "상단 정렬(maxY = anchor.maxY)"이
 * 여기서는 `top = anchor.top` 이다.
 *
 * 규칙(맥 그대로):
 * - 기본은 **캐릭터 왼쪽**(보드 right = anchor.left − gap), **상단 정렬**(보드 top = anchor.top).
 * - 왼쪽이 작업 영역 밖이면 **오른쪽으로 뒤집는다**(보드 left = anchor.right + gap) — 뒤집은 자리가 **온전히** 들어갈 때만.
 * - 뒤집어도 안 들어가면 뒤집지 않고 작업 영역 안으로 클램프한다(보드가 잘리는 것보다 캐릭터를 잠깐 가리는 편이 낫다).
 * - 세로는 클램프만 — 위↔아래 뒤집기는 없다.
 * - 클램프는 캐릭터 창과 **같은 함수**([OverlayGeometry.clampedOrigin]) — 두 창이 다르게 잘리면 안 된다(맥 주석).
 */
object TodoBoardAnchor {
    /** 보드 크기(DIP). 고정 — 내용이 늘어도 창이 자라지 않고 안에서 스크롤한다. */
    const val BOARD_WIDTH: Double = 300.0
    const val BOARD_HEIGHT: Double = 400.0

    /** 캐릭터와 보드 사이 간격(DIP). */
    const val GAP: Double = 10.0

    fun frame(anchor: OverlayRect, work: OverlayRect): OverlayRect {
        var x = anchor.left - GAP - BOARD_WIDTH
        if (x < work.left) {
            val flipped = anchor.right + GAP
            if (flipped + BOARD_WIDTH <= work.right) x = flipped
        }
        val y = anchor.top
        val origin = OverlayGeometry.clampedOrigin(x, y, BOARD_WIDTH, BOARD_HEIGHT, work)
        return OverlayRect(origin.x, origin.y, BOARD_WIDTH, BOARD_HEIGHT)
    }

    /**
     * 캐릭터가 볼 방향(맥 BoardFacing.direction): 보드 중심이 캐릭터 중심보다 왼쪽이면 −1, 아니면 1.
     * 두 중심이 같으면(보드가 캐릭터를 덮도록 클램프된 극단) 오른쪽.
     */
    fun facing(board: OverlayRect, character: OverlayRect): Int = if (board.centerX < character.centerX) -1 else 1
}
