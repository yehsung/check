import CheckCore
import CoreGraphics
import Foundation

/// 길건너 판 위 제스처 판정 — **순수 계산만** 한다(SwiftUI 없음, `#if os(iOS)` 없음). 그래서 macOS `swift test` 가
/// "손가락 좌표 → 아잉이가 뛴 방향"을 화면 없이 구동한다. 뷰(`GamesCrossyCanvas` 를 얹은 `GamesMiniGameScreen`)는
/// `DragGesture` 값을 그대로 넘기고 돌려받은 방향을 엔진에 먹이기만 한다(`GamesPlayController` 가 트래커를 쥔다).
///
/// ── 왜 테트리스 트래커를 못 쓰나 ───────────────────────────────────────────────────────────
/// 테트리스는 **누적 소비량**(`consumed`) 방식이다 — 한 번의 끌기가 셀 폭마다 한 칸씩, 여러 칸을 낸다. 길건너에는
/// 그 방식을 쓰면 안 된다: 앞으로 한 칸은 0.12초 애니메이션(`CrossyGame.hopSeconds`)이고 엔진은 뛰는 중 입력을
/// **한 칸만 줄 세운다**(그 뒤는 버린다). 즉 한 번의 끌기로 세 칸을 밀어 넣어도 두 칸은 그냥 사라지고, 손가락이
/// 간 거리와 아잉이가 간 거리가 어긋난다. 그래서 규약을 **한 접촉 = 한 칸**으로 좁혔다.
///
/// ── 떼기를 기다리지 않는다 ─────────────────────────────────────────────────────────────────
/// 길건너는 연타 게임이다(차 사이를 지나가는 틈이 한 칸 0.12초다). 손을 떼고 나서 뛰면 늦다 — 그래서 `onChanged`
/// 에서 문턱을 넘는 **그 순간** 방향 하나를 내고 접촉을 소진 표시한다. 테트리스의 `onEnded` 탭 판정과는 다른 축이다.
package struct CrossyGestureThresholds: Equatable, Sendable {
    /// 한 칸을 만드는 최소 이동(pt). **20 을 고른 근거**:
    /// · 탭 문턱 8pt(아래)보다 넉넉히 커야 손가락 흔들림이 뛰기가 되지 않는다. 8 바로 위(10~12)면 탭하려던 손가락이
    ///   방향으로 새고, 그 오인식은 길건너에서 **차에 치이는 것**이다(되돌릴 수 없다).
    /// · 테트리스의 한 칸 문턱은 화면 셀 폭(15~18pt)인데 그쪽은 **되돌릴 수 있는** 이동이라 더 민감해도 된다.
    ///   길건너는 한 칸이 생사라 한 단계 둔하게 잡았다.
    /// · 폰 화면에서 20pt 는 손가락 접촉 지름(약 44pt)의 절반 아래다 — 의도한 쓸기는 전부 넘고, 누르는 동안의 미세한
    ///   떨림(실측 관용값 5~10pt)은 안 넘는다.
    /// ⚠️ **실기로 아직 안 쟀다**(테트리스의 8pt·0.25초와 같은 사정 — 시뮬레이터 GUI 를 띄울 수 없다).
    /// TestFlight 10판에서 "쓸어도 안 간다"가 나오면 이 수부터 내린다.
    package var swipeMinDistance: CGFloat
    /// 탭으로 볼 최대 이동(pt). 테트리스와 **같은 수**다(같은 손가락, 같은 뜻 — 두 게임에서 다르면 몸이 못 배운다).
    package var tapMaxDistance: CGFloat
    /// 탭으로 볼 최대 시간(초). 테트리스와 같은 수다.
    package var tapMaxDuration: TimeInterval

    package init(swipeMinDistance: CGFloat = 20, tapMaxDistance: CGFloat = 8, tapMaxDuration: TimeInterval = 0.25) {
        self.swipeMinDistance = max(1, swipeMinDistance)
        self.tapMaxDistance = max(0, tapMaxDistance)
        self.tapMaxDuration = max(0, tapMaxDuration)
    }
}

/// 한 번의 접촉(손을 댄 순간 ~ 뗀 순간)을 **뛰기 한 번** 또는 **탭 한 번**으로 바꾼다.
///
/// 상태가 둘뿐이다: 지금 따라가는 접촉의 시작점과 "이 접촉이 이미 한 칸을 냈는가". 시작점으로 새 접촉을 알아보는
/// 까닭은 테트리스 트래커와 같다 — **`onEnded` 는 늘 오지 않는다**(시스템 제스처·전화 수신으로 취소되면 안 온다).
/// 불리언 하나로 두면 그때 소진 표시가 참인 채 굳어 다음 쓸기가 통째로 죽는다.
package struct CrossyGestureTracker: Equatable, Sendable {
    package private(set) var thresholds: CrossyGestureThresholds
    /// 지금 따라가고 있는 접촉의 시작점.
    private var startLocation: CGPoint?
    /// 이 접촉이 이미 한 칸을 냈는가(= 끌어서 여러 칸 가기는 없다).
    private var spent = false

    package init(thresholds: CrossyGestureThresholds = CrossyGestureThresholds()) {
        self.thresholds = thresholds
    }

    /// 이 접촉이 이미 한 칸을 냈는가(시험·화면 진단용).
    package var isSpent: Bool { spent }

    /// `onChanged` — 시작점부터의 누적 이동을 주면 **이번에 새로 생긴 방향 하나**를 돌려준다(없으면 nil).
    ///
    /// 큰 축 하나만 고른다: 대각으로 끌어도 두 방향이 같이 나가지 않는다(엔진이 둘째를 버리므로 '사라진 입력'이 된다).
    /// **동률이면 세로를 고른다** — 앞으로 가는 게임이고, 45° 쓸기의 의도는 거의 늘 '앞'이다.
    package mutating func drag(startLocation: CGPoint, translation: CGSize) -> CrossyGame.Direction? {
        if self.startLocation != startLocation {
            self.startLocation = startLocation
            spent = false
        }
        guard !spent else { return nil }
        let dx = translation.width
        let dy = translation.height
        guard max(abs(dx), abs(dy)) >= thresholds.swipeMinDistance else { return nil }
        spent = true
        if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
        // 화면 위(−height)가 앞이다 — `CrossyGame` 의 줄 번호는 앞이 +.
        return dy < 0 ? .forward : .back
    }

    /// `onEnded` — 이 접촉이 **탭**이었는가(진행 중이면 앞으로 한 칸, 시작 전·결과면 새 판). 상태를 비워 다음 접촉을 받는다.
    ///
    /// 한 칸을 이미 낸 접촉은 탭이 아니다(`spent` 가 그 증거다) — 안 그러면 한 번 쓸기가 **두 칸**이 된다.
    ///
    /// ⚠️ **죽은 구간이 있다**(테트리스와 같은 의도): 8pt 이상 20pt 미만을 움직이고 떼면 아무 일도 안 난다. 0.25초를
    /// 넘겨 천천히 떼도 같다. 애매한 입력을 아무 동작으로도 확정하지 않는 쪽을 골랐다 — 길건너에서 틀린 방향은
    /// 되돌릴 수 없다(차·강이 기다린다).
    package mutating func end(translation: CGSize, elapsed: TimeInterval) -> Bool {
        let moved = hypot(translation.width, translation.height)
        let isTap = !spent && moved < thresholds.tapMaxDistance && elapsed < thresholds.tapMaxDuration
        startLocation = nil
        spent = false
        return isTap
    }
}
