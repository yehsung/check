#if os(iOS)
import CheckCore
import SwiftUI

// 두 게임 캔버스가 함께 쓰는 조각(맥 `MiniGame.swift` 의 MiniGameOverlayCard · MiniGameCardChrome · MiniGameStageChip ·
// MiniGameScorePop 을 옮겼다). 캔버스는 무대 하늘이 늘 어둡기 때문에 라이트 모드에서도 맥 패널 색(CheckTheme)을 쓴다 —
// 게임 화면은 라이트·다크와 무관하게 같은 그림이다. 글자 크기는 캔버스 배율(`scale`)을 따라 커진다(판이 커진 만큼 같은 비율).

/// 시작 안내·결과 카드. w15: **불투명**(비평 14~19 — 반투명이라 플래피 기둥 선이 점수 뒤로 비치고 아잉이 카드 뒤에 흐리게 갇혔다) ·
/// 조작 안내는 버튼처럼 생긴 캡슐 대신 손가락 기호 + 글자(캔버스 전체가 누름 영역이다) · 보조 글은 한 단계 밝게.
struct GamesOverlayCard: View {
    let title: String
    var titleIsScore = false
    let subtitle: String
    var subtitleIsHighlighted = false
    let action: String
    var icon: String?
    /// 플래피: 기호 대신 실제 아잉 옆모습(벌새 기호 금지).
    var showsAing = false
    var tint: Color = CheckTheme.accent
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 6 * scale) {
            if showsAing {
                FlappyAingArt(size: 40 * scale)
                    .accessibilityHidden(true)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34 * scale, height: 34 * scale)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(titleIsScore ? .system(size: 30 * scale, weight: .heavy, design: .rounded) : .system(size: 17 * scale, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.system(size: (subtitleIsHighlighted ? 13 : 12) * scale, weight: subtitleIsHighlighted ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(subtitleIsHighlighted ? CheckTheme.working : CheckTheme.primaryText.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4 * scale) {
                Image(systemName: "hand.tap.fill")
                    .accessibilityHidden(true)
                Text(action)
            }
            .font(.system(size: 13 * scale, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.top, 4 * scale)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .frame(maxWidth: 240 * scale)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(CheckTheme.panelElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [tint.opacity(0.45), CheckTheme.border],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
        .accessibilityElement(children: .combine)
    }
}

/// 무대 이름 칩(두 게임이 같은 픽셀).
struct GamesStageChip: View {
    let stage: MiniGameStage
    var scale: CGFloat = 1

    var body: some View {
        Text(stage.name)
            .font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(stage.glow)
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 2 * scale)
            .background(Capsule().fill(stage.glow.opacity(0.16)))
            .overlay(Capsule().stroke(stage.glow.opacity(0.40), lineWidth: 1))
            .fixedSize()
    }
}

/// 잠깐 떠오르는 점수·판정 글씨("+100 · 완벽!" · "+1").
struct GamesScorePop: View {
    let text: String
    var caption: String?
    var tint: Color = CheckTheme.working
    var reduceMotion = false
    var scale: CGFloat = 1

    @State private var grow: CGFloat = 0.55
    @State private var lift: CGFloat = 0

    var body: some View {
        VStack(spacing: 1) {
            Text(text)
                .font(.system(size: 19 * scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.system(size: 10 * scale, weight: .bold))
            }
        }
        .foregroundStyle(tint)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .scaleEffect(reduceMotion ? 1 : grow)
        .offset(y: reduceMotion ? 0 : lift)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.30, bounce: 0.42)) { grow = 1 }
            withAnimation(.easeOut(duration: 0.55)) { lift = -14 * scale }
        }
        .accessibilityHidden(true)
    }
}

/// 화면 주사율(Hz). `UIScreen.main` 대신 지금 앞에 있는 창 장면의 화면을 읽는다(ProMotion 120 · 일반 60).
@MainActor
enum GamesDisplay {
    static var maximumFramesPerSecond: Int {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.maximumFramesPerSecond ?? MiniGameFrameRate.baselineFPS
    }
}
#endif
