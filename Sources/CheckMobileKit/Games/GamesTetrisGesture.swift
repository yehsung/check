import CoreGraphics
import Foundation

/// 테트리스 판 위 제스처 판정 — **순수 계산만** 한다(SwiftUI 없음, `#if os(iOS)` 없음). 그래서 macOS `swift test` 가
/// "손가락 움직임 → 조각 조작"을 화면 없이 구동한다. 뷰(`GamesTetrisCanvas`)는 `DragGesture` 값을 그대로 넘기고
/// 돌려받은 걸음을 엔진에 먹이기만 한다.
///
/// **왜 기존 두 게임의 제스처를 못 쓰나**: 플래피·타이밍 바는 판 어디든 첫 `onChanged` 를 **한 번의 탭**으로 접는다
/// (`GamesMiniGameScreen.swift:140-149`). 테트리스는 한 번의 끌기가 **여러 칸**을 만들고 행동도 셋(좌·우·소프트드롭)이라
/// 그 구조로는 표현이 안 된다.
///
/// **하드드롭은 여기 없다.** 제스처로 주지 않는다 — 소프트드롭 끌기와 구분이 어렵고 오인식 한 번이 곧 판 종료다. 버튼만이다.
package enum TetrisGestureStep: Equatable, Sendable {
    case moveLeft
    case moveRight
    case softDrop
}

/// 판정에 쓰는 임계값 **전부**. 실기로 되맞출 자리가 여기 하나뿐이도록 모아 둔다 — 감도 조정이 한 줄이 된다.
///
/// `cellWidth` 만 화면에서 온다(논리 셀 13pt × 화면 배율). 나머지 둘은 스펙 확정값이고 **아직 손가락으로 재지 않았다**
/// (시뮬레이터 GUI 를 띄울 수 없고 실기가 손에 없다). TestFlight 로 실제 10판을 잰 뒤 이 두 수만 고치면 된다.
package struct TetrisGestureThresholds: Equatable, Sendable {
    /// 한 칸을 만드는 이동 거리 = 화면 셀 폭. 손가락을 따라가게 하는 값이라 **거리 기준**이다(맥의 DAS/ARR 은 폰에 없다).
    package var cellWidth: CGFloat
    /// 탭으로 볼 최대 이동(pt).
    package var tapMaxDistance: CGFloat
    /// 탭으로 볼 최대 시간(초).
    package var tapMaxDuration: TimeInterval

    package init(cellWidth: CGFloat, tapMaxDistance: CGFloat = 8, tapMaxDuration: TimeInterval = 0.25) {
        self.cellWidth = max(1, cellWidth)
        self.tapMaxDistance = max(0, tapMaxDistance)
        self.tapMaxDuration = max(0, tapMaxDuration)
    }
}

/// 한 번의 끌기(손을 댄 순간 ~ 뗀 순간)를 걸음으로 바꾼다. `DragGesture` 의 `translation` 은 **시작점부터의 누적**이라
/// 이미 먹인 만큼을 이 타입이 기억한다.
///
/// **축 잠금**(스펙이 안 정한 것을 여기서 정한다): 먼저 문턱을 넘은 축이 그 끌기 동안 이긴다. 스펙은 가로·세로를 각각
/// 독립으로 적었는데, 그러면 살짝 비스듬한 가로 끌기가 **소프트드롭을 같이 만든다**. 20G 구간에서는 그 한 칸이 조각을
/// 바닥에 붙여 버려 의도하지 않은 확정이 된다 — 하드드롭에 제스처를 안 주기로 한 것과 같은 이유(오인식 = 조각 손실)로
/// 잠근다. 이 판단은 폰 전용이고 맥 조작과 무관하다.
package struct TetrisGestureTracker: Equatable, Sendable {
    /// 잠긴 축. 문턱을 처음 넘을 때 정해지고 끌기가 끝나면 풀린다.
    package enum Axis: Equatable, Sendable { case horizontal, vertical }

    package private(set) var thresholds: TetrisGestureThresholds
    package private(set) var axis: Axis?
    /// 이미 걸음으로 바꿔 먹인 양(축별). `translation` 이 누적값이라 이만큼을 빼고 본다.
    private var consumedX: CGFloat = 0
    private var consumedY: CGFloat = 0

    package init(thresholds: TetrisGestureThresholds) {
        self.thresholds = thresholds
    }

    /// 셀 폭이 바뀌면(화면 회전·기기 폭) 문턱을 갈아 끼운다. 진행 중인 끌기의 잠금·소비량은 건드리지 않는다.
    package mutating func updateCellWidth(_ width: CGFloat) {
        thresholds.cellWidth = max(1, width)
    }

    /// `onChanged` — 시작점부터의 누적 이동을 주면 이번에 새로 생긴 걸음들을 돌려준다.
    ///
    /// 문턱을 여러 배 넘겼으면 **그 배수만큼** 돌려준다(빠르게 긋는 손가락을 잃지 않는다). 방향이 도중에 바뀌면
    /// 반대 방향 걸음이 그대로 나온다 — 손가락 위치가 곧 조각 위치라는 규약이다.
    package mutating func drag(translation: CGSize) -> [TetrisGestureStep] {
        let cell = thresholds.cellWidth
        if axis == nil {
            // 아직 안 잠겼다: 먼저 한 칸을 만든 축이 이긴다. 둘 다 넘었으면 더 많이 간 쪽.
            let overX = abs(translation.width) >= cell
            let overY = abs(translation.height) >= cell
            if overX || overY {
                axis = (overX && overY)
                    ? (abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical)
                    : (overX ? .horizontal : .vertical)
            } else {
                return []
            }
        }
        switch axis {
        case .horizontal:
            let steps = Self.steps(total: translation.width, consumed: &consumedX, cell: cell)
            return (0..<abs(steps)).map { _ in steps > 0 ? .moveRight : .moveLeft }
        case .vertical:
            // 위로 끄는 것은 아무 일도 아니다(하드드롭도 회전도 아니다) — 아래로 간 몫만 센다.
            let steps = Self.steps(total: translation.height, consumed: &consumedY, cell: cell)
            return steps > 0 ? Array(repeating: .softDrop, count: steps) : []
        case nil:
            return []
        }
    }

    /// `onEnded` — 이 끌기가 **탭**(시계 회전)이었는가. 잠금·소비량을 비워 다음 끌기를 받을 준비를 한다.
    ///
    /// 탭은 "한 칸도 안 움직였다"가 아니라 **이동이 `tapMaxDistance` 미만이고 `tapMaxDuration` 안에 뗐다** 이다.
    /// 걸음을 하나라도 낸 끌기는 탭이 아니다(축이 잠겼다는 것이 그 증거다).
    package mutating func end(translation: CGSize, elapsed: TimeInterval) -> Bool {
        let moved = hypot(translation.width, translation.height)
        let isTap = axis == nil && moved < thresholds.tapMaxDistance && elapsed < thresholds.tapMaxDuration
        axis = nil
        consumedX = 0
        consumedY = 0
        return isTap
    }

    /// 누적 이동에서 **아직 안 먹인** 칸 수를 뽑고 소비량을 그만큼 올린다. 부호는 방향이다.
    private static func steps(total: CGFloat, consumed: inout CGFloat, cell: CGFloat) -> Int {
        let pending = total - consumed
        guard abs(pending) >= cell else { return 0 }
        let count = Int((abs(pending) / cell).rounded(.down))
        let signed = pending > 0 ? count : -count
        consumed += CGFloat(signed) * cell
        return signed
    }
}
