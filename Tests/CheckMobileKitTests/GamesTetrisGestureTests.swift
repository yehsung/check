import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

/// 테트리스 판 위 제스처 판정(`TetrisGestureTracker`). 뷰가 없어도 macOS 에서 손가락 움직임을 그대로 재현할 수 있게
/// 순수 계산으로 뽑아 둔 것을 값으로 잰다. 실기 감도 조정은 `TetrisGestureThresholds` 의 두 수만 바꾸면 되고,
/// 그때 이 테스트가 규칙(거리 기준·축 잠금·탭 판정)이 안 깨졌는지 지킨다.
@Suite("테트리스 제스처 판정")
struct GamesTetrisGestureTests {
    private static let cell: CGFloat = 20
    private func tracker() -> TetrisGestureTracker {
        TetrisGestureTracker(thresholds: TetrisGestureThresholds(cellWidth: Self.cell))
    }

    @Test("한 칸 문턱: 셀 폭을 넘어야 한 칸 · 넘은 배수만큼 한꺼번에 나온다")
    func stepsFollowTheFinger() {
        var t = tracker()
        let below = t.drag(translation: CGSize(width: 19, height: 0))
        #expect(below.isEmpty, "셀 폭 미만인데 칸이 움직였다")
        let one = t.drag(translation: CGSize(width: 20, height: 0))
        #expect(one == [.moveRight])
        // 누적값이라 40 은 '한 칸 더'다(두 칸이 아니다) — 이미 먹인 20 을 빼고 본다.
        let more = t.drag(translation: CGSize(width: 40, height: 0))
        #expect(more == [.moveRight])
        // 빠르게 그어 한 번에 세 칸을 넘겼다 — 손가락을 잃지 않는다.
        let burst = t.drag(translation: CGSize(width: 100, height: 0))
        #expect(burst == [.moveRight, .moveRight, .moveRight])
    }

    @Test("방향이 바뀌면 반대 걸음이 나온다(손가락 위치가 곧 조각 위치)")
    func reversingGivesBackTheSteps() {
        var t = tracker()
        let out = t.drag(translation: CGSize(width: 60, height: 0))
        #expect(out.count == 3)
        let back = t.drag(translation: CGSize(width: 20, height: 0))
        #expect(back == [.moveLeft, .moveLeft])
        let past = t.drag(translation: CGSize(width: -20, height: 0))
        #expect(past == [.moveLeft, .moveLeft])
    }

    @Test("소프트드롭은 아래로만 — 위로 끄는 것은 아무 일도 아니다")
    func softDropIsDownwardOnly() {
        var t = tracker()
        let down = t.drag(translation: CGSize(width: 0, height: 40))
        #expect(down == [.softDrop, .softDrop])
        var up = tracker()
        let upward = up.drag(translation: CGSize(width: 0, height: -60))
        #expect(upward.isEmpty, "위로 끌었는데 걸음이 나왔다")
    }

    @Test("축 잠금: 비스듬한 가로 끌기가 소프트드롭을 만들지 않는다(오인식 = 조각 손실)")
    func axisLockKeepsDiagonalsFromDropping() {
        var t = tracker()
        // 가로로 먼저 한 칸을 만들고, 그 뒤 세로로 세 칸을 더 갔다 — 세로는 무시돼야 한다.
        let first = t.drag(translation: CGSize(width: 22, height: 4))
        #expect(first == [.moveRight])
        #expect(t.axis == .horizontal)
        let later = t.drag(translation: CGSize(width: 24, height: 80))
        #expect(!later.contains(.softDrop), "잠긴 가로 축인데 소프트드롭이 샜다")

        // 반대도 같다: 세로가 먼저 잠기면 가로 이동이 안 샌다.
        var v = tracker()
        let firstDown = v.drag(translation: CGSize(width: 4, height: 22))
        #expect(firstDown == [.softDrop])
        #expect(v.axis == .vertical)
        let sideways = v.drag(translation: CGSize(width: 90, height: 24))
        #expect(!sideways.contains(.moveRight) && !sideways.contains(.moveLeft), "잠긴 세로 축인데 좌우 이동이 샜다")
    }

    @Test("둘 다 한 번에 문턱을 넘으면 더 많이 간 축이 이긴다")
    func theLongerAxisWinsTheLock() {
        var wide = tracker()
        _ = wide.drag(translation: CGSize(width: 50, height: 25))
        #expect(wide.axis == .horizontal)
        var tall = tracker()
        _ = tall.drag(translation: CGSize(width: 25, height: 50))
        #expect(tall.axis == .vertical)
    }

    @Test("탭 = 회전: 8pt 미만 · 0.25초 미만으로 뗐을 때만")
    func tapIsRotation() {
        var t = tracker()
        let quick = t.end(translation: CGSize(width: 3, height: 2), elapsed: 0.1)
        #expect(quick, "가만히 눌렀다 뗐는데 회전이 아니다")

        var slow = tracker()
        let held = slow.end(translation: .zero, elapsed: 0.4)
        #expect(!held, "오래 누르고 있다 뗀 것을 회전으로 읽었다")

        var far = tracker()
        let moved = far.end(translation: CGSize(width: 9, height: 0), elapsed: 0.1)
        #expect(!moved, "8pt 넘게 움직였는데 회전으로 읽었다")
    }

    @Test("걸음을 낸 끌기는 탭이 아니다 · 끝나면 잠금과 소비량이 풀린다")
    func draggingIsNeverATapAndStateResets() {
        var t = tracker()
        let steps = t.drag(translation: CGSize(width: 40, height: 0))
        #expect(steps.count == 2)
        // 손가락이 제자리로 돌아와 뗐다 — 이동 0 · 빠름이어도 회전이 아니다(축이 잠겼던 것이 증거).
        let tapped = t.end(translation: .zero, elapsed: 0.1)
        #expect(!tapped, "칸을 두 번 움직인 끌기를 회전으로 읽었다")
        #expect(t.axis == nil)
        // 다음 끌기는 처음부터다 — 앞 끌기의 소비량이 남아 첫 칸을 삼키면 안 된다.
        let fresh = t.drag(translation: CGSize(width: 20, height: 0))
        #expect(fresh == [.moveRight])
    }

    @Test("셀 폭이 바뀌어도 진행 중인 끌기의 잠금은 유지된다(화면 회전)")
    func cellWidthCanBeSwappedMidDrag() {
        var t = tracker()
        _ = t.drag(translation: CGSize(width: 22, height: 0))
        t.updateCellWidth(40)
        #expect(t.axis == .horizontal)
        #expect(t.thresholds.cellWidth == 40)
        // 새 문턱으로 잰다: 22 에서 42 로 갔지만 아직 40 을 못 넘었다.
        let short = t.drag(translation: CGSize(width: 42, height: 0))
        #expect(short.isEmpty)
        let long = t.drag(translation: CGSize(width: 62, height: 0))
        #expect(long == [.moveRight])
    }

    @Test("임계값은 0 이하로 내려가지 않는다(셀 폭 0 이면 나눗셈이 터진다)")
    func thresholdsAreGuarded() {
        let t = TetrisGestureThresholds(cellWidth: 0, tapMaxDistance: -5, tapMaxDuration: -1)
        #expect(t.cellWidth >= 1)
        #expect(t.tapMaxDistance == 0)
        #expect(t.tapMaxDuration == 0)
    }
}
