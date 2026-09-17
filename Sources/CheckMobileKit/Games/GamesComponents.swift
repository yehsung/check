#if os(iOS)
import SwiftUI

/// 게임 탭 누름 영역의 최소 한 변(pt) — HIG 44×44. 수락·거절처럼 8pt 간격으로 붙은 버튼이 작으면 잘못 눌러 판돈이 걸린다
/// (games-verify: 기본 글자에서 수락 35pt · 빠른 문구 31pt 실측).
enum GamesTouchTarget {
    static let minimum: CGFloat = 44
}

/// 게임 탭의 작은 버튼(채움 · 외곽선). 기반 `AingPrimaryButtonStyle` 과 같은 대비 규칙: 채움 위 글자는 `onAccent`
/// (`.borderedProminent` 는 다크에서 흰 글자라 대비가 모자라다 — 기반 부품 주석).
///
/// - 채움 영역 자체가 44×44 이상이다(누르는 곳 = 보이는 곳 — 붙은 두 버튼의 누름 영역이 겹치지 않게 바깥으로 넓히지 않는다).
/// - 접근성 글자 크기에서는 한 줄로 누르지 않고 줄을 바꾼다(AX5 에서 "같은 판돈으로…" 로 잘렸다).
struct GamesCompactButtonStyle: ButtonStyle {
    enum Kind { case filled, outline, destructive }

    var kind: Kind = .filled
    var fillsWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize

    func makeBody(configuration: Configuration) -> some View {
        let tint = kind == .destructive ? MobileTheme.danger : MobileTheme.accent
        let wraps = typeSize.isAccessibilitySize
        return configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(kind == .filled ? MobileTheme.onAccent : tint)
            .multilineTextAlignment(.center)
            .lineLimit(wraps ? nil : 1)
            .minimumScaleFactor(wraps ? 1 : 0.8)
            .fixedSize(horizontal: false, vertical: wraps)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: GamesTouchTarget.minimum, maxWidth: fillsWidth ? .infinity : nil, minHeight: GamesTouchTarget.minimum)
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
