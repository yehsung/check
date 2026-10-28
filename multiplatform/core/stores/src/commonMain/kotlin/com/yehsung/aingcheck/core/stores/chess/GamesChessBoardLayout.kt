// 원본: Sources/CheckMobileKit/Games/GamesChessBoardLayout.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint
import com.yehsung.aingcheck.core.stores.gomoku.BoardRect
import com.yehsung.aingcheck.core.stores.gomoku.BoardSize
import kotlin.math.floor

// 폰 체스 판 좌표 · 판 크기 예산(순수 — 데스크톱 JVM 시험으로 잰다). 맥 `ChessBoardGeometry` 와 **같은 식**이다. 오목 짝과 다른 점 둘:
// 좌표가 교차점이 아니라 **칸**이고, `orientation` 이 있다.
//
// INV-GamesChessBoardLayout-0ad8b563 이식: 뒤집기는 **이 타입 하나가 쥔다**(§6 ①). 체스는 내 색이 아래여야 읽히고 관전자는 백이 아래가
// 관례인데, 화면 좌표를 직접 셈하는 자리를 따로 만들면 **흑으로 두는 사람만** 판이 틀어진다 — 그리기·좌표 글자·애니메이션 방향이 전부
// `orientation` 한 값을 지난다.
//
// 옮기지 않은 것: `GamesChessFlightLoop.isPaused(flight:)`(애니메이션 프레임 루프의 배터리 계약 — `ChessMoveFlight` 를 받는다. 애니메이션은
// 화면 갈래 W4-a 몫이라 그 계약도 그쪽이 Compose `withFrameNanos` 루프로 다시 진다).

/** 판 그림의 좌표계. 여백이 없다: 칸이 판을 **꽉 채운다**(`cell = side / 8`). */
data class ChessPhoneBoardGeometry(
    /** 그림 한 변(pt). */
    val side: Double,
    /** 아래쪽에 오는 색(= 내 색 · 관전은 백). */
    val orientation: ChessColor = ChessColor.white,
) {
    val cell: Double get() = side / files.toDouble()

    /** 그 칸의 화면 열(0 = 왼쪽). */
    fun column(square: ChessSquare): Int = if (orientation == ChessColor.white) square.file else files - 1 - square.file

    /** 그 칸의 화면 행(0 = 맨 위). INV-GamesChessBoardLayout-ad8ae71d 이식: rank 는 **화면 y 와 반대로 자란다** — 백 판에서 한 번 뒤집는다. */
    fun row(square: ChessSquare): Int = if (orientation == ChessColor.white) ranks - 1 - square.rank else square.rank

    fun rect(square: ChessSquare): BoardRect =
        BoardRect(x = column(square).toDouble() * cell, y = row(square).toDouble() * cell, width = cell, height = cell)

    fun center(square: ChessSquare): BoardPoint {
        val box = rect(square)
        return BoardPoint(box.midX, box.midY)
    }

    /** 탭 위치가 든 칸(판 밖이면 null). **반 칸 관용이 없다** — 칸 안이 아니면 아무 칸도 아니다. */
    fun square(location: BoardPoint): ChessSquare? {
        if (cell <= 0 || location.x < 0 || location.y < 0 || location.x >= side || location.y >= side) return null
        val column = minOf(files - 1, (location.x / cell).toInt())
        val row = minOf(ranks - 1, (location.y / cell).toInt())
        val file = if (orientation == ChessColor.white) column else files - 1 - column
        val rank = if (orientation == ChessColor.white) ranks - 1 - row else row
        return ChessSquare.at(file, rank)
    }

    // MARK: 보간 — 움직이는 말 자리(애니메이션 갈래가 쓰는 산수 — 판정이 아니라 좌표다)

    /**
     * 두 칸 사이를 [t](0…1)만큼 간 **칸 크기 사각형**.
     * INV-GamesChessBoardLayout-a376eed0 이식: `t == 0` 이면 `rect(from)` 과, `t == 1` 이면 `rect(to)` 와 **바이트까지 같다** — 두 끝에서 보간이
     * 멈춘 판과 어긋나면 수가 시작할 때와 끝날 때 말이 한 번씩 튄다.
     * INV-GamesChessBoardLayout-5216fd93 이식: 여기에 `orientation` 이 **또 나오면 안 된다** — 뒤집기는 이미 `rect(of:)` 안에서 끝났다.
     */
    fun rect(from: ChessSquare, to: ChessSquare, t: Double): BoardRect {
        val start = rect(from)
        val end = rect(to)
        val k = minOf(1.0, maxOf(0.0, if (t.isNaN()) 0.0 else t))
        return BoardRect(
            x = start.minX + (end.minX - start.minX) * k,
            y = start.minY + (end.minY - start.minY) * k,
            width = start.width, height = start.height,
        )
    }

    /**
     * 칸 단위 오프셋 → 화면 오프셋.
     * INV-GamesChessBoardLayout-85710fbb 이식: **가장 틀리기 쉬운 자리다.** 잡힌 말이 밀리는 방향은 **판 좌표**(file/rank)로 들어온다 — 흑 판은
     * 뒤집혀 있어 같은 판 좌표가 화면에서 **반대쪽**이고, 거기에 **rank 는 한 번 더 뒤집힌다**(화면 y 는 아래로, rank 는 위로 자란다).
     */
    fun offset(fileDelta: Double, rankDelta: Double): BoardSize {
        val flip = if (orientation == ChessColor.white) 1.0 else -1.0
        return BoardSize(width = flip * fileDelta * cell, height = -flip * rankDelta * cell)
    }

    /** 가운데를 고정하고 비율만 바꾼 사각형. 음수 비율은 0 으로 떨어뜨린다(뒤집힌 사각형은 말을 거울로 그린다). */
    fun scaled(rect: BoardRect, scale: Double): BoardRect {
        val k = maxOf(0.0, if (scale.isNaN()) 0.0 else scale)
        val width = rect.width * k
        val height = rect.height * k
        return BoardRect(rect.midX - width / 2, rect.midY - height / 2, width, height)
    }

    companion object {
        const val files: Int = 8
        const val ranks: Int = 8
    }
}

/** 판 한 변을 **주어진 공간**에서 정한다. */
object GamesChessBoardMetrics {
    /** 8 로 나누어떨어지는 가장 작은 판(칸 20pt). 0 이나 음수를 내면 `cell` 이 0 이 되어 모든 탭을 삼킨다. */
    const val minimumSide: Double = 160.0

    /**
     * 주어진 공간에 들어가는 판 한 변.
     * INV-GamesChessBoardLayout-d7177c5b 이식: **높이 예산을 같이 본다** — 폰에서 너비만 보면 판 아래(사람 카드·기보·버튼)가 화면 밖으로 밀린다.
     * INV-GamesChessBoardLayout-ab37bf02 이식: **8 의 배수로 내린다** — 칸이 `side / 8` 이므로 나누어떨어지지 않으면 격자에 이음선이 보인다.
     */
    fun side(budget: BoardSize): Double {
        val raw = minOf(budget.width, budget.height)
        if (!raw.isFinite() || raw <= minimumSide) return minimumSide
        return floor(raw / ChessPhoneBoardGeometry.files) * ChessPhoneBoardGeometry.files
    }
}

/**
 * 체크 덮개가 설 칸을 고르는 **한 자리**(순수 — 맥 `ChessPanel.checkSquare` 와 같은 식).
 * INV-GamesChessBoardLayout-6ff74171 이식: **규칙을 돌리지 않는다** — 체크인지는 1:1 은 서버가, 로봇 판은 코어가 판정한 값으로 들어온다. 이 함수는
 * 그 깃발이 참일 때 배치에서 왕 칸을 읽을 뿐이다(조회이지 탐색이 아니다).
 * INV-GamesChessBoardLayout-9de56f41 이식: **끝난 판은 null 이다** — 결과 화면에 빨간 칸이 남으면 아직 두는 중처럼 읽힌다(두 끝을 다 본다).
 * INV-GamesChessBoardLayout-4f08de87 이식: 세 화면(대국·로봇·관전)이 **이 함수 하나**를 쓴다 — 세 번 적으면 한 화면만 조건을 놓친다.
 */
object GamesChessCheckMark {
    fun square(isInCheck: Boolean, isFinished: Boolean, turn: ChessColor?, position: ChessPosition?): ChessSquare? {
        if (!isInCheck || isFinished || turn == null || position == null) return null
        return position.kingSquare(turn)
    }
}
