#if os(iOS)
import CheckCore
import UIKit

/// 캡슐 뽑기 기계의 폰 햅틱(v0.3.54 · 폰 1.0.8). 기계 뷰(코어 `GachaMachineView`)는 박자만 말하고(`GachaMachineHapticEvent`),
/// 어떤 진동을 낼지는 이 플랫폼 몫이다 — 맥은 `GachaMachineNoHaptics`.
///
/// 시제품(`GachaPhoneHaptics`)과 같은 짝이다: 톱니 = 선택 틱 · 막힘 = 경고 · 한 바퀴 = 묵직 · 덜컹 = 부드럽게 · 떨어짐 = 단단 ·
/// 톡톡은 1→3 으로 세진다 · 황금 반전·공개 = 성공 · 조각 = 가볍게. 동작 줄이기에서 덜컹을 빼는 것은 기계가 이미 한다.
@MainActor
final class MeGachaHaptics: GachaMachineHaptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()
    private let select = UISelectionFeedbackGenerator()

    init() {
        // 첫 톱니가 늦게 울리지 않게 미리 깨운다(덮개가 뜰 때 한 번).
        [light, rigid, heavy, soft].forEach { $0.prepare() }
        select.prepare()
        notify.prepare()
    }

    func play(_ event: GachaMachineHapticEvent) {
        switch event {
        case .ratchet: select.selectionChanged()
        case .refuse: notify.notificationOccurred(.warning)
        case .commit: heavy.impactOccurred(intensity: 1)
        case .rumble: soft.impactOccurred(intensity: 0.6)
        case .land: rigid.impactOccurred(intensity: 0.7)
        case .tap(let n): rigid.impactOccurred(intensity: [0.5, 0.75, 1.0][min(max(n, 1), 3) - 1])
        case .goldFlip: notify.notificationOccurred(.success)
        case .reveal: notify.notificationOccurred(.success)
        case .goldReveal:
            heavy.impactOccurred(intensity: 1)
            notify.notificationOccurred(.success)
        case .shard: light.impactOccurred(intensity: 0.8)
        }
    }
}
#endif
