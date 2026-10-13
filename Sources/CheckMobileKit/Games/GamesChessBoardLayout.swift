import CheckCore
import CoreGraphics
import Foundation

// 폰 체스 판 좌표 · 판 크기 예산 · 프레임 루프 계약(순수 — macOS `swift test` 로 검증한다).
//
// 맥 `ChessBoardGeometry`(Sources/check/ChessPanel.swift)와 **같은 식**이다. 맥 타입은 앱 타깃 안이라 폰 모듈이
// 못 부르므로 식이 갈리지 않게 테스트가 두 끝(t=0/1)과 뒤집기를 되묻는다. 오목 짝은
// `GomokuPhoneBoardGeometry` 이고 다른 점 둘이 그대로다: 좌표가 교차점이 아니라 **칸**이고, `orientation` 이 있다.
//
// ★ 뒤집기는 **이 타입 하나가 쥔다**(§6 ①). 체스는 내 색이 아래여야 읽히고 관전자는 백이 아래가 관례인데,
//   화면 좌표를 직접 셈하는 자리를 따로 만들면 **흑으로 두는 사람만** 판이 틀어진다. 그리기·좌표 글자·
//   애니메이션 방향이 전부 `orientation` 한 값을 지난다.

/// 판 그림의 좌표계. 순수 값 — 탭 위치 ↔ 칸 변환을 결정적으로 잰다.
///
/// 여백이 없다: 칸이 판을 **꽉 채운다**(`cell = side / 8`). 좌표 글자(a~h · 1~8)는 테두리가 아니라
/// **가장자리 칸 안**에 그린다(맥과 같은 관례) — 테두리를 두면 칸이 격자에서 떨어져 반 픽셀 이음선이 생긴다.
package struct ChessPhoneBoardGeometry: Equatable, Sendable {
    /// 그림 한 변(pt).
    package let side: CGFloat
    /// 아래쪽에 오는 색(= 내 색 · 관전은 백).
    package var orientation: ChessColor

    package static let files = 8
    package static let ranks = 8

    package init(side: CGFloat, orientation: ChessColor = .white) {
        self.side = side
        self.orientation = orientation
    }

    package var cell: CGFloat { side / CGFloat(Self.files) }

    /// 그 칸의 화면 열(0 = 왼쪽).
    package func column(of square: ChessSquare) -> Int {
        orientation == .white ? square.file : Self.files - 1 - square.file
    }

    /// 그 칸의 화면 행(0 = 맨 위). ★ rank 는 **화면 y 와 반대로 자란다** — 백 판에서 한 번 뒤집는다.
    package func row(of square: ChessSquare) -> Int {
        orientation == .white ? Self.ranks - 1 - square.rank : square.rank
    }

    package func rect(of square: ChessSquare) -> CGRect {
        CGRect(x: CGFloat(column(of: square)) * cell, y: CGFloat(row(of: square)) * cell,
               width: cell, height: cell)
    }

    package func center(of square: ChessSquare) -> CGPoint {
        let box = rect(of: square)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// 탭 위치가 든 칸(판 밖이면 nil). **반 칸 관용이 없다** — 칸 안이 아니면 아무 칸도 아니다
    /// (오목은 교차점이라 "가장 가까운 점 ±0.5" 지만 체스는 칸이다).
    package func square(at location: CGPoint) -> ChessSquare? {
        guard cell > 0, location.x >= 0, location.y >= 0, location.x < side, location.y < side else { return nil }
        let column = min(Self.files - 1, Int(location.x / cell))
        let row = min(Self.ranks - 1, Int(location.y / cell))
        let file = orientation == .white ? column : Self.files - 1 - column
        let rank = orientation == .white ? Self.ranks - 1 - row : row
        return ChessSquare(file: file, rank: rank)
    }

    // MARK: 보간 — 움직이는 말 자리 (셋이 한 벌이다)

    /// 두 칸 사이를 `t`(0…1)만큼 간 **칸 크기 사각형**.
    ///
    /// ★ `t == 0` 이면 `rect(of: from)` 과, `t == 1` 이면 `rect(of: to)` 와 **바이트까지 같다** — 두 끝에서
    ///   보간이 멈춘 판과 어긋나면 수가 시작할 때와 끝날 때 말이 한 번씩 **튄다**.
    /// ★ 여기에 `orientation` 이 **또 나오면 안 된다**. 화면 사각형끼리 섞으므로 뒤집기는 이미 `rect(of:)`
    ///   안에서 끝났고, 한 번 더 하면 흑 판에서 말이 반대로 간다.
    package func rect(from: ChessSquare, to: ChessSquare, t: Double) -> CGRect {
        let start = rect(of: from), end = rect(of: to)
        let k = CGFloat(min(1, max(0, t.isNaN ? 0 : t)))
        return CGRect(x: start.minX + (end.minX - start.minX) * k,
                      y: start.minY + (end.minY - start.minY) * k,
                      width: start.width, height: start.height)
    }

    /// 칸 단위 오프셋 → 화면 오프셋.
    ///
    /// ★ **이 작업에서 가장 틀리기 쉬운 자리다.** 잡힌 말이 밀리는 방향은 모델에서 **판 좌표**(file/rank)로
    ///   들어온다(`ChessFlightFrame.Leaving` — 모델에는 화면이 없다). 흑으로 두는 사람의 판은 뒤집혀 있어
    ///   같은 판 좌표가 화면에서 **반대쪽**이고, 거기에 **rank 는 한 번 더 뒤집힌다**(화면 y 는 아래로 자라고
    ///   rank 는 위로 자란다 — `row(of:)` 와 같은 뒤집기다).
    ///   부호를 안 뒤집으면 **흑으로 두는 사람만** 잡힌 말이 잡은 말 쪽으로 되밀려 들어온다.
    package func offset(fileDelta: Double, rankDelta: Double) -> CGSize {
        let flip: CGFloat = orientation == .white ? 1 : -1
        return CGSize(width: flip * CGFloat(fileDelta) * cell,
                      height: -flip * CGFloat(rankDelta) * cell)
    }

    /// 가운데를 고정하고 비율만 바꾼 사각형(잡힌 말이 줄어드는 자리).
    /// 음수 비율은 0 으로 떨어뜨린다 — 뒤집힌 사각형을 `ChessPieceArt` 에 넘기면 말이 거울로 그려진다.
    package func scaled(_ rect: CGRect, by scale: Double) -> CGRect {
        let k = CGFloat(max(0, scale.isNaN ? 0 : scale))
        let width = rect.width * k, height = rect.height * k
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

/// 판 한 변을 **주어진 공간**에서 정한다.
package enum GamesChessBoardMetrics {
    /// 8 로 나누어떨어지는 가장 작은 판(칸 20pt). 예산이 터무니없이 작거나 숫자가 아닐 때의 바닥이다 —
    /// 0 이나 음수를 내면 `cell` 이 0 이 되어 `square(at:)` 이 모든 탭을 삼키고 판이 빈 그림이 된다.
    package static let minimumSide: CGFloat = 160

    /// 주어진 공간에 들어가는 판 한 변.
    ///
    /// ★ **높이 예산을 같이 본다.** 폰에서 너비만 보면 판 아래(사람 카드·기보·버튼)가 화면 밖으로 밀린다 —
    ///   맥은 1240×700 창이 고정이라 그 함정이 없었다.
    /// ★ **8 의 배수로 내린다.** 칸이 `side / 8` 이므로 나누어떨어지지 않으면 칸마다 반 픽셀이 남아 격자에
    ///   이음선이 보이고, 말 상자가 칸마다 1px씩 흔들린다(맥이 608pt = 76 × 8 을 고른 것과 같은 이유다).
    package static func side(fitting budget: CGSize) -> CGFloat {
        let raw = min(budget.width, budget.height)
        guard raw.isFinite, raw > minimumSide else { return minimumSide }
        return (raw / CGFloat(ChessPhoneBoardGeometry.files)).rounded(.down) * CGFloat(ChessPhoneBoardGeometry.files)
    }
}

/// 체크 덮개가 설 칸을 고르는 **한 자리**(순수 — 맥 `ChessPanel.checkSquare` 와 같은 식).
///
/// ★ **규칙을 돌리지 않는다.** 체크인지는 1:1 은 서버가, 로봇 판은 코어가 판정한 값(`isInCheck`)으로 들어온다 —
///   화면이 합법 수를 만들어 왕을 찾는 것은 금지다(§6 ④ · B5: 서버가 권위). 이 함수가 하는 일은 그 깃발이
///   참일 때 **배치에서 왕 칸을 읽는 것**뿐이고(`ChessPosition.kingSquare(of:)` — 탐색이 아니라 조회다),
///   그건 "판에 무엇이 서 있나" 라서 규칙 계산이 아니다.
///
/// ★ **끝난 판은 nil 이다.** 결과 화면에 빨간 칸이 남으면 아직 두는 중처럼 읽힌다(맥도 같은 가드다).
///   `turn` 도 끝난 판에서 nil 로 오지만 두 끝을 다 보는 까닭은, 둘 중 하나만 믿으면 응답 한 쪽이 옛 값을
///   들고 올 때 빨간 칸이 결과 화면까지 따라오기 때문이다.
///
/// ★ 세 화면(대국·로봇·관전)이 **이 함수 하나**를 쓴다. 두 줄짜리 식을 세 번 적으면 한 화면만 조건을
///   놓치고, 폰 뷰는 맥 스위트가 못 보므로 그 한 화면은 아무도 재지 않는다.
package enum GamesChessCheckMark {
    package static func square(isInCheck: Bool, isFinished: Bool, turn: ChessColor?,
                               position: ChessPosition?) -> ChessSquare? {
        guard isInCheck, !isFinished, let turn, let position else { return nil }
        return position.kingSquare(of: turn)
    }
}

/// 프레임 루프의 **배터리 계약**.
package enum GamesChessFlightLoop {
    /// `TimelineView(.animation(… paused:))` 에 넣는 값. 애니메이션이 없으면 **한 틱도 돌지 않아야 한다** —
    /// 체스 판은 대국 화면에 늘 떠 있어서, 여기가 false 로 굳으면 수를 안 둬도 60~120Hz 로 판을 다시 그린다.
    package static func isPaused(flight: ChessMoveFlight?) -> Bool { flight == nil }
}
