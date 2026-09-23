import Foundation
import SwiftUI

// v0.3.38 테트리스 **배치·색** — 맥 잎 뷰(`Sources/check/MiniGameTetris.swift`)에서 코어로 뗀 조각이다.
// 두 파일은 `CheckCoreSourceLayout.splitParts["MiniGameTetris.swift"]` 로 이어 읽는다(한쪽만 읽으면
// 부정 단언이 다른 쪽의 위반을 조용히 통과시킨다 — 그 함정은 CheckCoreSourceLayout 머리 주석에 있다).
//
// ── 폰도 이 배치를 쓴다 ───────────────────────────────────────────────────────────────────
// 폰 전용 레이아웃 타입을 만들지 않는다. 아래 검산은 **배율에 무관**하게 서고(합이 논리 292×302 로 닫힌다),
// 폰 배율은 맥(1.1781)보다 같거나 크다 — SE 343/292 = 1.1747 · iPhone15 361/292 = 1.2363 ·
// ProMax 398/292 = 1.3630. 게다가 논리 세로 = 21c + 29 ≤ 302 → c ≤ 13.0 이라 **가로를 어떻게 다시 짜도
// 판은 안 커진다**: 좌우 열을 걷어내도 얻는 것이 0 이고 홀드·넥스트만 잃는다.
// (폰에서 갈리는 것은 배치가 아니라 **글자 층**이다 — 8pt 캡션은 곱해도 iOS 하한 10pt 를 못 넘어 폰에서는
// 안 그리고 값 자리를 자기설명형으로 쓴다. 그건 폰 캔버스 쪽 일이고 이 표는 한 벌로 남는다.)

// MARK: - 배치 (논리 292×302 · 셀 13)

/// 캔버스 배치 상수. **논리 좌표(292×302)** 이고 실제 pt 는 `MiniGameProjection` 이 곱한다.
///
/// ── 왜 셀 13 인가(검산) ───────────────────────────────────────────────────────────────────
/// 판 10×20 을 논리 292×302 에 넣는다. 셀 12 면 판이 120×240 이라 세로가 62 남고, 셀 14 면 140×280 이라
/// 22 밖에 안 남는다. 남는 세로는 **버퍼행 한 칸 + 하단 밴드**가 나눠 써야 하는데 14 는 그 둘을 동시에 못 한다
/// (22 < 버퍼 14 + 밴드 21). 셀 13 은 판이 130×260 이고 위 여백이 **정확히 한 셀**이라 21행 버퍼를 온전히
/// 그린다 — 표준이 "스폰은 보이는 판 위에서 일어난다"고 정한 그 줄이다.
///
/// ── 가로 검산(합 292) ─────────────────────────────────────────────────────────────────────
/// 12(여백) + 61(왼쪽 열) + 8(거터) + 130(판) + 8(거터) + 61(오른쪽 열) + 12(여백) = 292.
/// 바깥 여백 12 의 근거: 캔버스 모서리 둥글기가 실제 14pt(`MiniGamePanel.canvasStack`)이고 배율이
/// 1.178 이라 논리 11.88 이다 — 12 면 모서리 원 바로 바깥이다.
///
/// ── 세로 검산(합 302) ─────────────────────────────────────────────────────────────────────
/// 13(버퍼행) + 260(판 20행) + 4(틈) + 21(하단 밴드) + 4(바닥 여백) = 302.
/// 왼쪽 열 바닥(줄 값 257+16 = 273) · 오른쪽 열 바닥(25 + 5×44 + 4×7 = 273) · 판 바닥(13+260 = 273)이
/// **같은 줄**이다. 셋 중 하나만 고치면 그 정렬이 깨진다.
package enum TetrisLayout {
    /// 두 게임과 같은 논리 판. 캔버스(344×356)와 비율이 같아 레터박스가 0.11pt 뿐이다.
    package static let logicalSize = MiniGameCanvas.logicalSize

    package static let cell: CGFloat = 13
    package static let outerMargin: CGFloat = 12
    package static let columnWidth: CGFloat = 61
    package static let gutter: CGFloat = 8

    package static let boardX = outerMargin + columnWidth + gutter                  // 81
    package static let boardWidth = cell * CGFloat(TetrisGame.columns)              // 130
    package static let rightColumnX = boardX + boardWidth + gutter                  // 219

    /// 버퍼행(표준 21행)의 윗변. 판 위 한 셀이 전부 이 줄이다.
    package static let bufferY: CGFloat = 0
    /// 보이는 20행의 윗변.
    package static let boardTopY = cell                                             // 13
    /// 보이는 20행의 아랫변. 양쪽 열도 여기서 끝난다.
    package static let boardBottomY = boardTopY + cell * CGFloat(TetrisGame.visibleRows)  // 273

    /// 하단 밴드(점수 · B2B/콤보).
    package static let bandY: CGFloat = 277
    package static let bandHeight: CGFloat = 21
    /// 글자는 이 범위 안에 둔다 — 논리 x 12 는 모서리 원(실제 반지름 14)의 경계와 맞닿는다.
    package static let textMinX: CGFloat = 16
    package static let textMaxX: CGFloat = 276

    // ── 왼쪽 열(x 12…73): 홀드 · 무대 칩 · 레벨 · 줄 ──────────────────────────────────────
    package static let labelY: CGFloat = 13
    package static let labelHeight: CGFloat = 10
    /// 홀드 상자와 넥스트 1번 슬롯이 **같은 y** 다(25…69) — 두 열의 첫 상자가 한 줄에 서야 짝으로 읽힌다.
    package static let boxY: CGFloat = 25
    package static let boxHeight: CGFloat = 44
    package static let stageChipY: CGFloat = 89
    package static let stageChipHeight: CGFloat = 16
    package static let levelCaptionY: CGFloat = 213
    package static let levelValueY: CGFloat = 222
    package static let linesCaptionY: CGFloat = 248
    package static let linesValueY: CGFloat = 257
    package static let captionHeight: CGFloat = 9
    package static let valueHeight: CGFloat = 16

    // ── 오른쪽 열(x 219…280): 넥스트 5개 ─────────────────────────────────────────────────
    package static let slotGap: CGFloat = 7
    /// 미니 조각 한 칸. **홀드와 넥스트가 같은 값을 쓴다** — 두 벌로 두면 같은 조각이 자리마다 다른 크기가 된다.
    /// 여유 검산: 슬롯 = 미니셀×2 + 패딩 12 ≤ 44 → 미니셀 ≤ 16. 9 는 7단계 여유가 남아 줄일 이유가 없다.
    package static let miniCell: CGFloat = 9

    /// n 번째 넥스트 슬롯(0부터)의 윗변.
    package static func slotY(_ index: Int) -> CGFloat {
        boxY + CGFloat(index) * (boxHeight + slotGap)
    }

    /// 판 좌표(행 0 = 맨 위) → 논리 사각형. 보이는 20행 + 그 위 버퍼 한 줄만 이 식이 뜻을 가진다.
    package static func cellRect(row: Int, column: Int) -> CGRect {
        CGRect(x: boardX + CGFloat(column) * cell,
               y: boardTopY + CGFloat(row - TetrisGame.firstVisibleRow) * cell,
               width: cell, height: cell)
    }

    /// 판 우물 전체(버퍼행 포함).
    package static var wellRect: CGRect {
        CGRect(x: boardX, y: bufferY, width: boardWidth, height: boardBottomY - bufferY)
    }
}

// MARK: - 조각 색

/// 조각 7종의 색. **표준 배색**(I 하늘 · J 파랑 · L 주황 · O 노랑 · S 초록 · T 보라 · Z 빨강)을 따르되
/// 이 저장소의 대비 규약에 맞춰 값을 조였다.
///
/// ── 왜 조각이 배경보다 확실히 밝아야 하는가 ───────────────────────────────────────────────
/// 이 저장소는 같은 자리에서 한 번 당했다: 플래피 기둥을 밝은 `structure` 로 채웠더니 한낮 무대에서
/// 캐릭터와 휘도비가 **1.01:1** 이라 겹치는 순간 플레이어가 통째로 사라졌다(2026-09-10 5개 무대 실측,
/// `MiniGameStage.structureDeep` 주석). 그래서 규약이 "몸통은 어둡게, 밝은 색은 윤곽에만"으로 뒤집혔다.
/// 테트리스는 그 규약의 **반대쪽**이다 — 조각이 곧 몸통이고 판이 배경이므로, 판(우물)을 어둡게 깔고
/// 조각을 밝게 둬야 같은 결론이 나온다.
///
/// ── 실측(WCAG 상대휘도 비) ────────────────────────────────────────────────────────────────
/// 우물은 `wellInk`(0.02,0.03,0.06)를 **불투명도 0.72** 로 무대 하늘 위에 얹은 색이다. 무대 5종 × (하늘 위·
/// 아래) 열 가지 합성 중 가장 밝은 것은 노을 아래쪽(0.213,0.114,0.110 · L=0.0176)이고, 그 위에서 잰
/// 조각별 최소 대비는 다음과 같다(python3 전수, 2026-09-23):
///   I 9.22 · J **4.31** · L 7.21 · O 11.89 · S 9.35 · T 5.40 · Z 4.59   → **최솟값 4.31:1**
/// 플래피가 남긴 문턱(2.0:1)의 두 배 이상이다. 불투명도 0.72 를 내리면 이 최솟값이 곧장 따라 내려간다 —
/// 0.55 로 낮추면 노을 우물이 L=0.0369 가 되어 J 가 2.9:1 까지 떨어진다.
///
/// ── 조각끼리도 갈려야 한다 ────────────────────────────────────────────────────────────────
/// 휘도비는 조각 사이를 가르지 못한다(I 하늘과 S 초록은 1.01:1 인데 눈으로는 전혀 다르다). 그래서
/// **채널 최대 차**로 쟀다: 21쌍 전부 0.27(69/255) 이상이고 최솟값이 L 주황 ↔ Z 빨강이다. 표준 배색에서
/// 원래 가장 가까운 쌍이라, 주황을 더 노랗게(0.99,0.60,0.16) 빨강을 더 붉게(0.95,0.33,0.36) 벌려 놓았다.
package enum TetrisPalette {
    /// 우물 바닥 잉크. 무대 하늘 위에 `wellOpacity` 로 얹는다.
    package static let wellInk = (r: 0.02, g: 0.03, b: 0.06)
    /// 우물 불투명도. **위 대비 실측의 기준값이다** — 내리면 조각-배경 대비가 그대로 내려간다.
    package static let wellOpacity: Double = 0.72

    /// 조각 색 원장(sRGB). 테스트가 이 표를 읽어 무대 5종과의 대비를 다시 잰다 — 색을 바꾸면 거기서 걸린다.
    package static let rgb: [TetrisGame.Piece: (r: Double, g: Double, b: Double)] = [
        .i: (0.33, 0.85, 0.92),
        .j: (0.36, 0.50, 0.96),
        .l: (0.99, 0.60, 0.16),
        .o: (0.97, 0.89, 0.33),
        .s: (0.44, 0.88, 0.45),
        .t: (0.74, 0.48, 0.97),
        .z: (0.95, 0.33, 0.36),
    ]

    package static var wellColor: Color { Color(red: wellInk.r, green: wellInk.g, blue: wellInk.b) }

    package static func color(_ piece: TetrisGame.Piece) -> Color {
        let c = rgb[piece] ?? (r: 1, g: 1, b: 1)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// 칸 윗변의 하이라이트. 인접한 두 칸을 가르는 것은 1pt 틈이고, 이 띠는 **덩어리에 두께를 준다**.
    package static let cellHighlight = Color.white.opacity(0.22)
    /// 고스트(하드드롭 착지 자리). 조각색을 옅게 — 색이 같아야 "이 조각이 저기 앉는다"가 읽힌다.
    /// 0.26 은 우물 대비 1.36:1 로, 보이되 굳은 칸(4.31:1 이상)과 절대 혼동되지 않는 세기다.
    package static let ghostOpacity: Double = 0.26
    /// 홀드를 이미 쓴 상태 표시(조각을 흐리고 테두리를 위험색으로).
    package static let spentOpacity: Double = 0.35
}
