// 원본: Sources/CheckCore/ChessPieceArt.swift @ 3bd04bd
//
// 체스 기물 여섯 종의 **벡터 실루엣**(맥·폰과 한 벌의 좌표). 단위 사각형(0…1, y 는 위가 0) 안에 적고 칸에 맞춰 늘린다.
// 유니코드 글리프(♔♕♖♗♘♙)는 설치된 글꼴이 정해 굵기·세로 중심·속 빈 정도가 기기마다 달라진다 — 모양을 우리가 쥔다.
// 각 말은 **칸 가운데를 반드시 덮는다**(칸 중앙 50% 상자에서 잉크를 세는 렌더 판정이 "말이 있다"를 가른다).
// 색·선 굵기는 부르는 쪽(판 그림 · 승격 시트)이 쥐고, 여기는 **모양만** 쥔다.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Path
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind

object ChessPieceArt {
    /** 말이 차지하는 칸 안 비율(나머지는 칸 여백). */
    const val FILL_FRACTION: Float = 0.86f

    /** 칸 사각형 안에서 말이 그려지는 상자. */
    fun box(cell: Rect): Rect {
        val side = minOf(cell.width, cell.height) * FILL_FRACTION
        return Rect(cell.center.x - side / 2, cell.center.y - side / 2, cell.center.x + side / 2, cell.center.y + side / 2)
    }

    /** 그 말의 채움 경로(여러 조각이 한 Path — nonZero 로 채우면 합쳐진다). */
    fun path(kind: ChessPieceKind, cell: Rect): Path {
        val frame = box(cell)
        val path = Path()
        fun point(x: Float, y: Float) = Offset(frame.left + x * frame.width, frame.top + y * frame.height)
        fun addRect(x0: Float, y0: Float, x1: Float, y1: Float, radius: Float = 0f) {
            val a = point(x0, y0)
            val b = point(x1, y1)
            val r = radius * frame.width
            path.addRoundRect(RoundRect(Rect(a, b), CornerRadius(r, r)))
        }
        fun addCircle(cx: Float, cy: Float, r: Float) {
            val c = point(cx, cy)
            val radius = r * frame.width
            path.addOval(Rect(c.x - radius, c.y - radius, c.x + radius, c.y + radius))
        }
        fun addPolygon(points: List<Pair<Float, Float>>) {
            val first = points.firstOrNull() ?: return
            val start = point(first.first, first.second)
            path.moveTo(start.x, start.y)
            for (p in points.drop(1)) {
                val o = point(p.first, p.second)
                path.lineTo(o.x, o.y)
            }
            path.close()
        }
        when (kind) {
            ChessPieceKind.pawn -> {
                addRect(0.22f, 0.80f, 0.78f, 0.91f, radius = 0.04f)
                addPolygon(listOf(0.30f to 0.80f, 0.70f to 0.80f, 0.60f to 0.50f, 0.40f to 0.50f))
                addCircle(0.50f, 0.37f, 0.155f)
            }
            ChessPieceKind.rook -> {
                addRect(0.17f, 0.80f, 0.83f, 0.91f, radius = 0.04f)
                addPolygon(listOf(0.25f to 0.80f, 0.75f to 0.80f, 0.69f to 0.40f, 0.31f to 0.40f))
                addRect(0.21f, 0.30f, 0.79f, 0.41f)
                addRect(0.21f, 0.15f, 0.34f, 0.31f)
                addRect(0.435f, 0.15f, 0.565f, 0.31f)
                addRect(0.66f, 0.15f, 0.79f, 0.31f)
            }
            ChessPieceKind.knight -> {
                addRect(0.18f, 0.80f, 0.82f, 0.91f, radius = 0.04f)
                addPolygon(
                    listOf(
                        0.24f to 0.80f, 0.76f to 0.80f, 0.76f to 0.70f, 0.68f to 0.60f,
                        0.74f to 0.46f, 0.82f to 0.34f, 0.74f to 0.20f, 0.58f to 0.12f,
                        0.46f to 0.14f, 0.42f to 0.24f, 0.28f to 0.32f, 0.20f to 0.44f,
                        0.34f to 0.50f, 0.44f to 0.44f, 0.40f to 0.58f, 0.30f to 0.70f,
                    ),
                )
            }
            ChessPieceKind.bishop -> {
                addRect(0.19f, 0.80f, 0.81f, 0.91f, radius = 0.04f)
                addPolygon(listOf(0.28f to 0.80f, 0.72f to 0.80f, 0.62f to 0.52f, 0.38f to 0.52f))
                addRect(0.33f, 0.45f, 0.67f, 0.53f, radius = 0.03f)
                addPolygon(listOf(0.50f to 0.12f, 0.64f to 0.30f, 0.66f to 0.46f, 0.34f to 0.46f, 0.36f to 0.30f))
                addCircle(0.50f, 0.10f, 0.055f)
            }
            ChessPieceKind.queen -> {
                addRect(0.15f, 0.80f, 0.85f, 0.91f, radius = 0.04f)
                addPolygon(listOf(0.25f to 0.80f, 0.75f to 0.80f, 0.67f to 0.47f, 0.33f to 0.47f))
                addRect(0.27f, 0.40f, 0.73f, 0.48f, radius = 0.03f)
                addPolygon(
                    listOf(
                        0.21f to 0.40f, 0.17f to 0.19f, 0.31f to 0.31f, 0.38f to 0.15f,
                        0.50f to 0.29f, 0.62f to 0.15f, 0.69f to 0.31f, 0.83f to 0.19f, 0.79f to 0.40f,
                    ),
                )
                for (tip in listOf(0.17f to 0.17f, 0.38f to 0.13f, 0.50f to 0.27f, 0.62f to 0.13f, 0.83f to 0.17f)) addCircle(tip.first, tip.second, 0.05f)
            }
            ChessPieceKind.king -> {
                addRect(0.15f, 0.80f, 0.85f, 0.91f, radius = 0.04f)
                addPolygon(listOf(0.25f to 0.80f, 0.75f to 0.80f, 0.67f to 0.45f, 0.33f to 0.45f))
                addRect(0.27f, 0.38f, 0.73f, 0.46f, radius = 0.03f)
                addPolygon(listOf(0.27f to 0.38f, 0.31f to 0.24f, 0.50f to 0.33f, 0.69f to 0.24f, 0.73f to 0.38f))
                addRect(0.455f, 0.05f, 0.545f, 0.25f)
                addRect(0.37f, 0.10f, 0.63f, 0.175f)
            }
        }
        return path
    }
}
