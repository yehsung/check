// 원본: Sources/CheckCore/TetrisDuelBoard.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

/**
 * 테트리스 1:1 상대 판 스냅숏 글자판(서버 `tetris_players.board` 칸의 모양, v0.3.60).
 * 보이는 20행 × 10칸을 위에서 아래로, 행 우선으로 200글자. 글자는 `.IJLOSTZG` 아홉 개뿐(서버 CHECK 와 같다).
 * 떨어지는 조각은 담지 않는다. 순수 값 변환이고 시계·화면이 없다.
 */
sealed interface TetrisDuelCell {
    data object Empty : TetrisDuelCell
    data class Piece(val piece: TetrisGame.Piece) : TetrisDuelCell
    data object Garbage : TetrisDuelCell
}

object TetrisDuelBoard {
    /** 글자판 길이(보이는 20행 × 10칸). */
    const val cellCount: Int = TetrisGame.visibleRows * TetrisGame.columns

    /** 쓰는 글자 전부(서버 CHECK 와 같은 집합). */
    const val alphabet: String = ".IJLOSTZG"

    /** 빈 판. */
    val emptyText: String get() = ".".repeat(cellCount)

    /** 엔진 판을 글자판으로(보이는 행만, 방해 줄 칸은 `G`). */
    fun encode(game: TetrisGame): String = encode(game.board, game.garbageMask)

    /** 판·방해 줄 표시(둘 다 40행)를 글자판으로. 행이 모자라면 빈 칸으로 본다. */
    fun encode(board: List<List<TetrisGame.Piece?>>, garbageMask: List<Int>): String {
        val out = StringBuilder(cellCount)
        for (row in TetrisGame.firstVisibleRow until TetrisGame.totalRows) {
            val cells = if (row < board.size) board[row] else emptyList()
            val mask = if (row < garbageMask.size) garbageMask[row] else 0
            for (column in 0 until TetrisGame.columns) {
                val piece = if (column < cells.size) cells[column] else null
                if (piece == null) {
                    out.append('.')
                    continue
                }
                out.append(if ((mask and (1 shl column)) != 0) 'G' else letter(piece))
            }
        }
        return out.toString()
    }

    /** 글자판 → 20행 × 10칸. 길이가 200(UTF-8 바이트)이 아니거나 모르는 글자가 있으면 null(깨진 판을 그리지 않는다). */
    fun decode(text: String): List<List<TetrisDuelCell>>? {
        val bytes = text.encodeToByteArray()
        if (bytes.size != cellCount) return null
        val rows = ArrayList<List<TetrisDuelCell>>(TetrisGame.visibleRows)
        var row = ArrayList<TetrisDuelCell>(TetrisGame.columns)
        for (byte in bytes) {
            val cell = cell(byte) ?: return null
            row.add(cell)
            if (row.size == TetrisGame.columns) {
                rows.add(row)
                row = ArrayList(TetrisGame.columns)
            }
        }
        return rows
    }

    /** 서버 CHECK 와 같은 판정(정확히 200바이트 · 아홉 글자만). */
    fun isValid(text: String): Boolean {
        val bytes = text.encodeToByteArray()
        return bytes.size == cellCount && bytes.all { cell(it) != null }
    }

    /** 조각 글자(대문자 한 자). */
    fun letter(piece: TetrisGame.Piece): Char = when (piece) {
        TetrisGame.Piece.i -> 'I'
        TetrisGame.Piece.j -> 'J'
        TetrisGame.Piece.l -> 'L'
        TetrisGame.Piece.o -> 'O'
        TetrisGame.Piece.s -> 'S'
        TetrisGame.Piece.t -> 'T'
        TetrisGame.Piece.z -> 'Z'
    }

    private fun cell(byte: Byte): TetrisDuelCell? = when (byte.toInt().toChar()) {
        '.' -> TetrisDuelCell.Empty
        'I' -> TetrisDuelCell.Piece(TetrisGame.Piece.i)
        'J' -> TetrisDuelCell.Piece(TetrisGame.Piece.j)
        'L' -> TetrisDuelCell.Piece(TetrisGame.Piece.l)
        'O' -> TetrisDuelCell.Piece(TetrisGame.Piece.o)
        'S' -> TetrisDuelCell.Piece(TetrisGame.Piece.s)
        'T' -> TetrisDuelCell.Piece(TetrisGame.Piece.t)
        'Z' -> TetrisDuelCell.Piece(TetrisGame.Piece.z)
        'G' -> TetrisDuelCell.Garbage
        else -> null
    }
}
