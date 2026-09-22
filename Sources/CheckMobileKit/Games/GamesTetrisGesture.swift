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
/// `cellWidth` 만 화면에서 온다(논리 셀 13pt × 화면 배율).
///
/// ⚠️ **나머지 둘(8pt · 0.25초)은 확정값이 아니다.** 출처는 SPEC 부록 폰 절인데, 그 부록은 난이도 재튜닝 **이전** 산출이라
/// 이미 낡은 값이 셋 드러났다(`maxStep` · 무대 경계 · 토큰 주기). 그리고 어느 쪽이든 **아직 손가락으로 재지 않았다** —
/// 시뮬레이터 GUI 를 띄울 수 없고 실기가 손에 없다. TestFlight 로 실제 10판을 잰 뒤 이 두 수를 고치는 것이 남은 일이다.
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
/// 독립으로 적었는데, 그건 규약이 아니라 안 따져 본 자리다. 그대로 두면 살짝 비스듬한 가로 끌기가 **소프트드롭을 같이
/// 만든다.**
///
/// 무엇을 잃는가 — **확정(락)이 아니다.** 소프트드롭은 `gravitySeconds(L) / 20` 인 **가속된 중력**일 뿐이고, 조각을
/// 잠그는 것은 락딜레이와 접지 리셋 한도다. 잃는 것은 하나뿐이다: **조준한 곳보다 낮은 자리에 떨어뜨린다.**
///
/// 아픈 구간은 조각이 실제로 공중에 있는 **초반**이다. 레벨표를 계산해 보면 20칸을 내려오는 데 걸리는 시간이
/// L1 7.10초 · L3 3.79 · L5 1.88 · L7 0.86 · L9 0.36 · L11 0.14 · L13 0.05 · L15(=20G) 0.016초다.
/// 즉 **L1~7 에서만** 손가락이 끼어들 틈이 있고, 그 뒤로는 애초에 개입할 시간이 없다.
///
/// 접지 예산은 이 판단과 **무관하다**(한때 근거로 적었다가 계산해 보고 지웠다): `lockResetLimit` 은 L≤15 에서 15 로
/// 고정이고 줄어드는 것은 L16 부터인데, L15 가 이미 20G 라 그 구간에서는 소프트드롭이 할 일이 없다. 예산이 귀한 곳과
/// 소프트드롭이 먹히는 곳이 **겹치지 않는다.**
///
/// 즉 하드드롭에 제스처를 안 주기로 한 것과 **같은 규율**(오인식이 비싸다)이되 기전은 '확정'이 아니라 '자리'다.
/// 이 판단은 폰 전용이고 맥 조작과 무관하다.
package struct TetrisGestureTracker: Equatable, Sendable {
    /// 잠긴 축. 문턱을 처음 넘을 때 정해지고 끌기가 끝나면 풀린다.
    package enum Axis: Equatable, Sendable { case horizontal, vertical }

    package private(set) var thresholds: TetrisGestureThresholds
    package private(set) var axis: Axis?
    /// 이미 걸음으로 바꿔 먹인 양(축별). `translation` 이 누적값이라 이만큼을 빼고 본다.
    private var consumedX: CGFloat = 0
    private var consumedY: CGFloat = 0
    /// 지금 따라가고 있는 접촉의 시작점. **`onEnded` 를 못 받는 경우가 있어서** 이걸로 새 끌기를 알아본다.
    private var startLocation: CGPoint?

    package init(thresholds: TetrisGestureThresholds) {
        self.thresholds = thresholds
    }

    /// 셀 폭이 바뀌면 문턱을 갈아 끼운다. **화면 회전은 아니다** — 앱은 세로 고정 아이폰 전용이다
    /// (`ios/project.yml` 의 `UISupportedInterfaceOrientations` 는 Portrait 하나). 끌기 **도중에** 바뀔 일은
    /// 사실상 없고(폭은 기기가 정한다), 이 함수는 화면이 트래커를 다시 만들지 않고 재사용할 때를 위한 것이다.
    package mutating func updateCellWidth(_ width: CGFloat) {
        thresholds.cellWidth = max(1, width)
    }

    /// `onChanged` — 시작점부터의 누적 이동을 주면 이번에 새로 생긴 걸음들을 돌려준다.
    ///
    /// 문턱을 여러 배 넘겼으면 **그 배수만큼** 돌려준다(빠르게 긋는 손가락을 잃지 않는다). 방향이 도중에 바뀌면
    /// 반대 방향 걸음이 그대로 나온다 — 손가락 위치가 곧 조각 위치라는 규약이다.
    package mutating func drag(startLocation: CGPoint, translation: CGSize) -> [TetrisGestureStep] {
        // **새 접촉인가.** `onEnded` 는 항상 오지 않는다(시스템 제스처·전화 수신 등으로 취소되면 안 온다). 그때 잠금과
        // 소비량이 남아 있으면, 다음 끌기의 `translation` 은 0 부터 시작하는데 `consumed` 는 옛 값이라
        // `pending = 0 − consumed` 가 **큰 반대 부호**가 되어 손도 안 댄 이동이 우수수 나온다. 입력을 잃는 게 아니라
        // **없는 입력을 만든다** — 그쪽이 훨씬 나쁘다. 시작점이 바뀌면 상태를 버리고 새로 시작한다.
        if self.startLocation != startLocation {
            self.startLocation = startLocation
            axis = nil
            consumedX = 0
            consumedY = 0
        }
        let cell = thresholds.cellWidth
        if axis == nil {
            // 아직 안 잠겼다: 먼저 한 칸을 만든 축이 이긴다. 둘 다 넘었으면 더 많이 간 쪽.
            //
            // **위로 끄는 것은 축을 잠그지 않는다.** 위로는 아무 동작도 없는데(하드드롭도 회전도 아니다) 잠가 버리면
            // 그 끌기 내내 좌우가 통째로 죽는다 — 손가락을 살짝 올렸다 옆으로 가는 흔한 동작이 먹통이 된다.
            let overX = abs(translation.width) >= cell
            let overY = translation.height >= cell
            if overX || overY {
                axis = (overX && overY)
                    ? (abs(translation.width) >= translation.height ? .horizontal : .vertical)
                    : (overX ? .horizontal : .vertical)
            } else {
                return []
            }
        }
        switch axis {
        case .horizontal:
            // 가로는 **환불한다** — 손가락을 되돌리면 조각도 되돌아온다(손가락 위치가 곧 조각 위치).
            let steps = Self.steps(total: translation.width, consumed: &consumedX, cell: cell)
            return (0..<abs(steps)).map { _ in steps > 0 ? .moveRight : .moveLeft }
        case .vertical:
            // 세로는 **래칫이다(환불 없음)**. 소프트드롭은 되돌릴 수 없는 동작인데(조각은 안 올라간다) 환불하면
            // 같은 구간을 아래위로 문지르는 것만으로 소프트드롭이 무한정 나온다 — 칸당 1점이라 **점수 위조**가 된다.
            // 그래서 내려간 최대치만 기억하고 그 너머로 갈 때만 걸음을 낸다.
            let steps = Self.steps(total: max(translation.height, consumedY), consumed: &consumedY, cell: cell)
            return steps > 0 ? Array(repeating: .softDrop, count: steps) : []
        case nil:
            return []
        }
    }

    /// `onEnded` — 이 끌기가 **탭**(시계 회전)이었는가. 잠금·소비량을 비워 다음 끌기를 받을 준비를 한다.
    ///
    /// 탭은 "한 칸도 안 움직였다"가 아니라 **이동이 `tapMaxDistance` 미만이고 `tapMaxDuration` 안에 뗐다** 이다.
    /// 걸음을 하나라도 낸 끌기는 탭이 아니다(축이 잠겼다는 것이 그 증거다).
    ///
    /// ⚠️ **죽은 구간이 있다**(의도한 것): 8pt 이상 움직였지만 셀 폭(화면에서 대략 15~18pt)에 못 미친 채 떼면 회전도
    /// 이동도 안 난다. 0.25초를 넘겨 천천히 떼도 마찬가지다. 조용히 삼키는 쪽을 고른 이유는 애매한 입력을 **아무 동작으로도
    /// 확정하지 않기** 위해서다 — 회전이든 이동이든 틀리면 조각이 엉뚱한 자리에 간다. 다만 이 구간이 실사용에서 얼마나
    /// 자주 밟히는지는 **아직 손가락으로 안 쟀다**. 실기 10판에서 "탭이 자꾸 씹힌다"가 나오면 `tapMaxDuration` 부터 늘린다.
    package mutating func end(translation: CGSize, elapsed: TimeInterval) -> Bool {
        let moved = hypot(translation.width, translation.height)
        let isTap = axis == nil && moved < thresholds.tapMaxDistance && elapsed < thresholds.tapMaxDuration
        axis = nil
        consumedX = 0
        consumedY = 0
        startLocation = nil
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
