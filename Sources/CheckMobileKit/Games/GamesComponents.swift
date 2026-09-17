#if os(iOS)
import SwiftUI

/// 게임 탭의 작은 버튼(채움 · 외곽선). 기반 `AingPrimaryButtonStyle` 과 같은 대비 규칙: 채움 위 글자는 `onAccent`
/// (`.borderedProminent` 는 다크에서 흰 글자라 대비가 모자라다 — 기반 부품 주석).
struct GamesCompactButtonStyle: ButtonStyle {
    enum Kind { case filled, outline, destructive }

    var kind: Kind = .filled
    var fillsWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = kind == .destructive ? MobileTheme.danger : MobileTheme.accent
        return configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(kind == .filled ? MobileTheme.onAccent : tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind == .filled ? tint : tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(kind == .filled ? 0 : 0.45), lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    /// 데모 스크린샷(`-AingCheckGamesDemo bottom`)에서만 스크롤을 맨 아래에서 시작한다. Release 에서는 아무것도 안 한다.
    @ViewBuilder
    func gamesDemoScrollAnchor(isDemo: Bool) -> some View {
        #if DEBUG
        if GamesDemoSeed.current(isDemo: isDemo) == .bottom {
            defaultScrollAnchor(.bottom)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
