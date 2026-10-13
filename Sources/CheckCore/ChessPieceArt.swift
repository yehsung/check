import SwiftUI

// v0.3.50 — 체스 말 그림을 **맥·폰이 한 벌로** 쓴다.
//
// 0.3.44~0.3.48 에서는 이 코드가 맥 전용 자리(`Sources/check/ChessPanel.swift`)에 있었다. 폰 체스 판을 만들면서
// 복사하지 않고 **올렸다** — 두 벌이면 한쪽만 고쳐지고, 갈라진 것을 아무도 모른다(같은 수리를 직전 오목
// 작업에서 `avatar(for:photoURL:characterHint:)` 에 했다: `CheckAvatarView` → `AppUserCharacters`).
//
// 올릴 수 있는 근거: 이 파일에 AppKit·UIKit 의존이 **0건**이다. SwiftUI `Path` 와 `CGRect` 만 쓴다 —
// `GraphicsContext.fill/stroke` 를 부르는 쪽(맥 `ChessBoardView` · 폰 `GamesChessBoardCanvas`)이 색과 선 굵기를
// 쥐고, 여기는 **모양만** 쥔다. 그래서 두 플랫폼이 같은 실루엣을 그리고, 한 번 고치면 둘 다 고쳐진다.
// MARK: - 말 그림(벡터)

/// 고전 체스 기물 여섯 종의 **벡터 실루엣**. 단위 사각형(0…1, y 는 위가 0) 안에 적고 칸에 맞춰 늘린다.
///
/// 왜 벡터인가: 유니코드 글리프(♔♕♖♗♘♙)는 설치된 폰트가 정한다 — 폰트마다 굵기·세로 중심·속 빈 정도가
/// 달라지고(어떤 폰트는 흑 기물만 속을 채운다) 체스 폰트가 없는 맥에서는 두부(􀀀)가 된다. 판에서 폰과
/// 비숍을 못 가리는 그림은 기능 고장이므로 모양을 우리가 쥔다.
///
/// 각 말은 **칸 가운데를 반드시 덮는다**(렌더 검증이 칸 중앙 50% 상자에서 잉크를 센다 — 폰이 작아 가운데가
/// 비면 "말이 안 그려졌다"와 구분되지 않는다).
package enum ChessPieceArt {
    /// 말이 차지하는 칸 안 비율(나머지는 칸 여백). 0.86 = 76pt 칸에서 65pt 말.
    package static let fillFraction: CGFloat = 0.86

    /// 칸 사각형 안에서 말이 그려지는 상자.
    package static func box(in cell: CGRect) -> CGRect {
        let side = min(cell.width, cell.height) * fillFraction
        return CGRect(x: cell.midX - side / 2, y: cell.midY - side / 2, width: side, height: side)
    }

    /// 그 말의 채움 경로(여러 조각이 한 Path 에 들어간다 — nonZero 로 채우면 합쳐진다).
    package static func path(for kind: ChessPieceKind, in cell: CGRect) -> Path {
        let frame = box(in: cell)
        var path = Path()

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: frame.minX + x * frame.width, y: frame.minY + y * frame.height)
        }
        func addRect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, radius: CGFloat = 0) {
            let origin = point(x0, y0), far = point(x1, y1)
            let box = CGRect(x: origin.x, y: origin.y, width: far.x - origin.x, height: far.y - origin.y)
            if radius > 0 {
                let r = radius * frame.width
                path.addRoundedRect(in: box, cornerSize: CGSize(width: r, height: r), style: .continuous)
            } else {
                path.addRect(box)
            }
        }
        func addCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            let c = point(cx, cy)
            let radius = r * frame.width
            path.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        func addPolygon(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: point(first.0, first.1))
            for p in points.dropFirst() { path.addLine(to: point(p.0, p.1)) }
            path.closeSubpath()
        }

        switch kind {
        case .pawn:
            addRect(0.22, 0.80, 0.78, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.30, 0.80), (0.70, 0.80), (0.60, 0.50), (0.40, 0.50)])  // 몸통
            addCircle(0.50, 0.37, 0.155)                           // 머리
        case .rook:
            addRect(0.17, 0.80, 0.83, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.69, 0.40), (0.31, 0.40)])  // 몸통
            addRect(0.21, 0.30, 0.79, 0.41)                        // 어깨 띠
            addRect(0.21, 0.15, 0.34, 0.31)                        // 성벽 셋
            addRect(0.435, 0.15, 0.565, 0.31)
            addRect(0.66, 0.15, 0.79, 0.31)
        case .knight:
            addRect(0.18, 0.80, 0.82, 0.91, radius: 0.04)          // 받침
            addPolygon([                                            // 말 머리 옆모습(오른쪽을 본다)
                (0.24, 0.80), (0.76, 0.80), (0.76, 0.70), (0.68, 0.60),
                (0.74, 0.46), (0.82, 0.34), (0.74, 0.20), (0.58, 0.12),
                (0.46, 0.14), (0.42, 0.24), (0.28, 0.32), (0.20, 0.44),
                (0.34, 0.50), (0.44, 0.44), (0.40, 0.58), (0.30, 0.70)
            ])
        case .bishop:
            addRect(0.19, 0.80, 0.81, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.28, 0.80), (0.72, 0.80), (0.62, 0.52), (0.38, 0.52)])  // 몸통
            addRect(0.33, 0.45, 0.67, 0.53, radius: 0.03)          // 목 띠
            addPolygon([                                            // 주교관(미트라)
                (0.50, 0.12), (0.64, 0.30), (0.66, 0.46), (0.34, 0.46), (0.36, 0.30)
            ])
            addCircle(0.50, 0.10, 0.055)                           // 꼭지
        case .queen:
            addRect(0.15, 0.80, 0.85, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.67, 0.47), (0.33, 0.47)])  // 몸통
            addRect(0.27, 0.40, 0.73, 0.48, radius: 0.03)          // 목 띠
            addPolygon([                                            // 다섯 뿔 왕관
                (0.21, 0.40), (0.17, 0.19), (0.31, 0.31), (0.38, 0.15),
                (0.50, 0.29), (0.62, 0.15), (0.69, 0.31), (0.83, 0.19), (0.79, 0.40)
            ])
            for tip in [(0.17, 0.17), (0.38, 0.13), (0.50, 0.27), (0.62, 0.13), (0.83, 0.17)] {
                addCircle(tip.0, tip.1, 0.05)                      // 뿔 끝 구슬
            }
        case .king:
            addRect(0.15, 0.80, 0.85, 0.91, radius: 0.04)          // 받침
            addPolygon([(0.25, 0.80), (0.75, 0.80), (0.67, 0.45), (0.33, 0.45)])  // 몸통
            addRect(0.27, 0.38, 0.73, 0.46, radius: 0.03)          // 목 띠
            addPolygon([(0.27, 0.38), (0.31, 0.24), (0.50, 0.33), (0.69, 0.24), (0.73, 0.38)])  // 왕관
            addRect(0.455, 0.05, 0.545, 0.25)                      // 십자가 세로
            addRect(0.37, 0.10, 0.63, 0.175)                       // 십자가 가로
        }
        return path
    }
}
