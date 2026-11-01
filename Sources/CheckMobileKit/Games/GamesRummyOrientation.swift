import CheckCore
import Foundation
#if os(iOS)
import OSLog
import SwiftUI
import UIKit
#endif

// 폰 아잉 큐브 **판 화면만 가로**(설계서 §10.1 · 사용자 답 "이 화면만 가로"). 앱의 나머지는 세로다.
//
// ── 잠금이 가로에 남지 않는 까닭 ──
// 저장된 잠금이 **없다.** 방향은 언제나 지금 상태에서 계산한다(`GamesStore.rummyInterfaceOrientation` → `GamesRummyOrientationRule`). 그래서 '푸는 코드를 잊은 길'이 있을 수 없다:
// 화면이 사라졌거나(`isRummyScreenVisible`) · 판이 끝났거나 · 세션이 끝났으면(`reset`) 그 순간 답이 세로다. 시스템이 묻는 답(`MobileAppModel.supportedInterfaceOrientations`)도 같은 값이고,
// 값을 시스템에 알리는 자리(`GamesRummyOrientationDriver`)는 앱 루트 한 곳이라 큐브 화면이 사라져도 살아 있다.
// 앱을 내려도 방향은 안 바뀐다(앱을 내리는 것은 화면을 떠나는 것이 아니다) — 돌아오면 드라이버가 한 번 더 알린다.

package enum GamesRummyInterfaceOrientation: Equatable, Sendable {
    case portrait, landscape
}

/// 언제 가로인가. 맥 스위트가 표로 재는 자리다.
package enum GamesRummyOrientationRule {
    /// 판이 도는 판 화면 + 결과의 [최종 판]. 로비 · 방 · 등수 화면은 세로.
    package static func wants(phase: RummyStore.Phase, isScreenVisible: Bool, finalBoardShown: Bool) -> Bool {
        guard isScreenVisible else { return false }
        switch phase {
        case .playing: return true
        case .finished: return finalBoardShown
        case .lobby, .room: return false
        }
    }

    package static func orientation(phase: RummyStore.Phase, isScreenVisible: Bool, finalBoardShown: Bool) -> GamesRummyInterfaceOrientation {
        wants(phase: phase, isScreenVisible: isScreenVisible, finalBoardShown: finalBoardShown) ? .landscape : .portrait
    }
}

#if os(iOS)

/// 방향 값 → 시스템. 상태를 쥐지 않는다.
enum GamesRummyOrientationLock {
    private static let logger = Logger(subsystem: "com.yehsung.aingcheck", category: "rummy-orientation")

    static func mask(_ orientation: GamesRummyInterfaceOrientation) -> UIInterfaceOrientationMask {
        orientation == .landscape ? .landscape : .portrait
    }

    /// 시스템에 지금 방향을 알린다: 물어볼 값이 바뀌었으니 다시 물으라고 하고(`setNeeds…`) · 그 방향으로 돌려 달라고 청한다. 실패는 로그만 남긴다.
    @MainActor
    static func apply(_ orientation: GamesRummyInterfaceOrientation) {
        let mask = mask(orientation)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                logger.error("방향 전환 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// 앱 루트에 하나. 값이 바뀌면 알리고, 앱이 돌아오면 한 번 더 알린다. 잎 뷰라 판 상태가 바뀌어도 루트가 다시 안 그려진다.
struct GamesRummyOrientationDriver: View {
    let games: GamesStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: games.rummyInterfaceOrientation, initial: true) { _, orientation in
                GamesRummyOrientationLock.apply(orientation)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { GamesRummyOrientationLock.apply(games.rummyInterfaceOrientation) }
            }
    }
}

public extension MobileAppModel {
    /// 앱 델리게이트가 시스템에 돌려주는 값. 큐브 판 화면 밖에서는 언제나 세로다.
    var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        GamesRummyOrientationLock.mask(games.rummyInterfaceOrientation)
    }
}

#endif
