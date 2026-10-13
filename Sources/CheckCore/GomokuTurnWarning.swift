import Foundation
import SwiftUI

// 0.3.51 — 오목 **내 차례 마지막 3초**에 판 안쪽 가장자리가 빨갛게 빛난다(맥·폰 한 벌).
//
// ── 왜 코어에 있나 ──
// 문턱(3초)·세기·그림이 두 플랫폼에서 갈리면 한쪽만 고쳐진다(5초·10초 링 문턱이 이미 세 뷰에 복사돼 있다 — 그 꼴을 되풀이하지 않는다).
// 그래서 **판정(순수 계산)과 그림(`GraphicsContext` 에 긋는 법)** 을 여기 한 곳에 두고, 시계를 읽는 일만 각 플랫폼의 잎 뷰가 한다
// (맥 `GomokuBoardTimeWarning` · 폰 `GamesGomokuBoardTimeWarning`). `ChessPieceArt` · `MiniGameEffects.glow` 와 같은 수법이다.
//
// ── 지키는 약속 ──
//   · **내 차례에만** 선다(AI 판의 내 차례 포함). 상대 차례·관전·AI 차례·멈춘 AI 시계·끝난 판·판 없음은 마감이 없거나 내 것이 아니다 —
//     상대 차례의 빨간 판은 내가 할 수 있는 일이 없는데 "내 시간이 끝나 간다"로 읽힌다(상대 카드의 링이 이미 5초부터 빨갛다).
//   · `nil` 은 **언제나 꺼짐**이다. 링이 쓰는 `remainingSeconds(...) ?? 0` 을 그대로 베끼면 마감이 없는 순간(AI 차례·멈춘 시계)에 0초로 읽혀
//     판이 빨갛게 켜진다 — 이 타입의 입력은 Optional 그대로 받는다.
//   · 0초에도 켜진 채다. 표시 마감은 서버 유예(2초)를 뺀 값이라 0초 뒤에도 서버가 대신 둘 때까지 다음 상태가 늦게 온다 — 그 사이 내 링도 빨간 0초다.
//   · 스토어에 매초 바뀌는 값을 두지 않는다(GomokuStore 규칙 ⑥). 세기는 잎 뷰가 그 순간의 남은 초로 계산해 바로 그린다.
//   · 그림은 **정적**이다 — 반복 애니메이션·blur·shadow 가 없다(repeatForever 는 창을 닫아도 합성기를 태웠다 · blur 는 미니게임 규칙이 금한다).
//     안쪽으로 겹친 둥근 사각형 선 몇 겹이 바깥에서 안으로 옅어질 뿐이고, 세기만 3초 → 0초로 조금 오른다(5Hz 틱마다 한 단계).

/// 내 차례 마지막 몇 초의 판 테두리 경고 — 판정과 그림. 시계를 읽지 않는다(남은 초는 부르는 잎 뷰가 넘긴다).
package nonisolated enum GomokuTurnWarning {
    /// 경고가 서는 남은 시간(초, **이하**). 링 숫자는 올림이라 "3초"가 보이는 순간과 정확히 같다(2.4초도 "3초"로 보인다).
    package static let lowTimeSeconds: TimeInterval = 3
    /// 3초 순간의 세기(옅게 시작). 0초에 `maximumIntensity` 까지 곧게 오른다.
    package static let minimumIntensity: Double = 0.55
    package static let maximumIntensity: Double = 1.0

    /// 이 판에서 경고가 **설 수 있는가** — 끝나지 않았고, 내 차례이고, 마감이 돈다.
    /// 마감이 nil 인 경우(AI 차례 · 창이 가려져 멈춘 AI 시계 · 끝난 판)와 상대 차례는 전부 false 다.
    /// 잎 뷰는 이 값으로 TimelineView 를 멈추고, **본문에서 한 번 더** 본다 — 멈춘 TimelineView 는 마지막 그림을 들고 있다.
    package static func watchesMyClock(_ match: GomokuMatchState?) -> Bool {
        guard let match, !match.isFinished, match.deadline != nil, let turn = match.turn else { return false }
        return turn == match.myColor
    }

    /// 남은 초가 경고 구간인가. nil(마감 없음) · NaN · 무한대는 꺼짐이고, 3.0 이하(0 포함)는 켜짐이다.
    package static func isActive(remaining: Double?) -> Bool {
        guard let remaining, remaining.isFinite else { return false }
        return remaining <= lowTimeSeconds
    }

    /// 빛의 세기(0…1). 꺼짐이면 0, 3초에 `minimumIntensity`, 0초(와 그 아래)에 `maximumIntensity`.
    package static func intensity(remaining: Double?) -> Double {
        guard isActive(remaining: remaining), let remaining else { return 0 }
        let left = min(1, max(0, remaining / lowTimeSeconds))
        return minimumIntensity + (maximumIntensity - minimumIntensity) * (1 - left)
    }

    // MARK: 그림

    /// 빛의 색(sRGB). 금수 X(0.87, 0.16, 0.18)·마지막 수 점(0.95, 0.30, 0.26)보다 **파랑이 많은 진홍**이다 —
    /// 판 위 빨간 표시를 픽셀로 찾는 렌더 검증이 서로를 헷갈리지 않게 하고, 사람 눈에도 "판에 놓인 표시"가 아니라 "판 둘레의 빛"으로 읽힌다.
    package static let tintRed: Double = 0.90
    package static let tintGreen: Double = 0.06
    package static let tintBlue: Double = 0.30
    package static var tint: Color { Color(red: tintRed, green: tintGreen, blue: tintBlue) }
    /// 빛이 들어오는 깊이(판 한 변의 비율). 0.024 = 608pt 판에서 14.6pt. 가장자리 돌은 판 끝에서 한 변의 3.1% 안쪽부터라
    /// (여백 6% − 돌 반지름) 빛이 돌에 닿지 않는다 — 폰 판도 같은 비율이라 같은 관계다.
    package static let depthRatio: CGFloat = 0.024
    /// 판 모서리 둥글기(판 그림과 같은 값 — `GomokuBoardView` · `GamesGomokuBoardCanvas` 의 side × 0.025).
    package static let cornerRatio: CGFloat = 0.025
    /// 겹 수와 가장 바깥 겹의 불투명도(세기 1 일 때). 안쪽 겹일수록 제곱으로 옅어진다.
    package static let layerCount = 8
    package static let peakOpacity: Double = 0.7

    /// 한 변 `side` 인 판의 안쪽 가장자리에 빛을 긋는다. `intensity` 가 0 이하면 아무것도 안 긋는다.
    /// **판의 둥근 사각형 밖으로는 한 픽셀도 안 나간다**(먼저 그 모양으로 자른다) — 맥 판 위 머리글까지 12pt 뿐이고,
    /// 렌더 검증의 아래 여백 띠가 판 아래 2pt 부터다. 바깥으로 번지는 그림자식 빛은 그 둘을 칠한다.
    package static func drawEdgeGlow(into context: inout GraphicsContext, side: CGFloat, intensity: Double) {
        guard intensity > 0, side > 0, intensity.isFinite else { return }
        let strength = min(1, intensity)
        let frame = CGRect(x: 0, y: 0, width: side, height: side)
        let corner = side * cornerRatio
        let band = side * depthRatio / CGFloat(layerCount)
        var layer = context
        layer.clip(to: Path(roundedRect: frame, cornerRadius: corner, style: .continuous))
        for index in 0..<layerCount {
            let inset = band * (CGFloat(index) + 0.5)
            let falloff = 1 - Double(index) / Double(layerCount)
            let opacity = strength * peakOpacity * falloff * falloff
            layer.stroke(
                Path(roundedRect: frame.insetBy(dx: inset, dy: inset), cornerRadius: max(0, corner - inset), style: .continuous),
                with: .color(tint.opacity(opacity)),
                lineWidth: band
            )
        }
    }
}
