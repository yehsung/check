import Foundation

// v0.3.60 테트리스 1:1 — 상대 판 스냅숏 글자판(서버 `tetris_players.board` 칸의 모양).
//
// 보이는 20행 × 10칸을 **위에서 아래로, 행 우선**으로 200글자에 담는다. 글자는 `.IJLOSTZG` 아홉 개뿐이다:
// `.` 빈 칸 · 조각 일곱(색) · `G` 방해 줄. 서버 CHECK 가 같은 모양을 강제한다(null 이거나 정확히 200글자 ·
// `!~ '[^.IJLOSTZG]'`). 떨어지는 조각은 담지 않는다 — 굳은 판만이 상대에게 뜻이 있고, 1초 보고 주기로는 조각 위치가
// 어차피 끊겨 보인다. 순수 값 변환이고 시계·화면이 없다.

/// 상대 판의 칸 하나.
package enum TetrisDuelCell: Equatable, Sendable {
    case empty
    case piece(TetrisGame.Piece)
    case garbage
}

package enum TetrisDuelBoard {
    /// 글자판 길이(보이는 20행 × 10칸).
    package static let cellCount = TetrisGame.visibleRows * TetrisGame.columns
    /// 쓰는 글자 전부(서버 CHECK 와 같은 집합).
    package static let alphabet = ".IJLOSTZG"

    /// 빈 판(준비 보고 등 판이 아직 없을 때).
    package static var emptyText: String { String(repeating: ".", count: cellCount) }

    /// 엔진 판을 글자판으로. 보이는 행(`firstVisibleRow` …)만 담고, 방해 줄 칸은 `G` 다.
    package static func encode(_ game: TetrisGame) -> String {
        encode(board: game.board, garbageMask: game.garbageMask)
    }

    /// 판·방해 줄 표시(둘 다 40행)를 글자판으로. 행이 모자라면 빈 칸으로 본다.
    package static func encode(board: [[TetrisGame.Piece?]], garbageMask: [UInt16]) -> String {
        var out = ""
        out.reserveCapacity(cellCount)
        for row in TetrisGame.firstVisibleRow..<TetrisGame.totalRows {
            let cells = row < board.count ? board[row] : []
            let mask = row < garbageMask.count ? garbageMask[row] : 0
            for column in 0..<TetrisGame.columns {
                guard column < cells.count, let piece = cells[column] else {
                    out.append(".")
                    continue
                }
                out.append(mask & (UInt16(1) << column) != 0 ? "G" : letter(for: piece))
            }
        }
        return out
    }

    /// 글자판 → 20행 × 10칸(행 0 = 보이는 판 맨 위). 길이가 200이 아니거나 모르는 글자가 있으면 nil 이다
    /// (서버가 같은 규칙으로 막으므로 정상 경로에서는 일어나지 않는다 — 그래도 깨진 판을 그리지 않는다).
    package static func decode(_ text: String) -> [[TetrisDuelCell]]? {
        let bytes = Array(text.utf8)
        guard bytes.count == cellCount else { return nil }
        var rows: [[TetrisDuelCell]] = []
        rows.reserveCapacity(TetrisGame.visibleRows)
        var row: [TetrisDuelCell] = []
        row.reserveCapacity(TetrisGame.columns)
        for byte in bytes {
            guard let cell = cell(forByte: byte) else { return nil }
            row.append(cell)
            if row.count == TetrisGame.columns {
                rows.append(row)
                row = []
                row.reserveCapacity(TetrisGame.columns)
            }
        }
        return rows
    }

    /// 서버 CHECK 와 같은 판정(정확히 200글자 · 아홉 글자만).
    package static func isValid(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == cellCount && bytes.allSatisfy { cell(forByte: $0) != nil }
    }

    /// 조각 글자(대문자 한 자).
    package static func letter(for piece: TetrisGame.Piece) -> Character {
        switch piece {
        case .i: return "I"
        case .j: return "J"
        case .l: return "L"
        case .o: return "O"
        case .s: return "S"
        case .t: return "T"
        case .z: return "Z"
        }
    }

    private static func cell(forByte byte: UInt8) -> TetrisDuelCell? {
        switch byte {
        case UInt8(ascii: "."): return .empty
        case UInt8(ascii: "I"): return .piece(.i)
        case UInt8(ascii: "J"): return .piece(.j)
        case UInt8(ascii: "L"): return .piece(.l)
        case UInt8(ascii: "O"): return .piece(.o)
        case UInt8(ascii: "S"): return .piece(.s)
        case UInt8(ascii: "T"): return .piece(.t)
        case UInt8(ascii: "Z"): return .piece(.z)
        case UInt8(ascii: "G"): return .garbage
        default: return nil
        }
    }
}
