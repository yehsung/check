#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 캐릭터 초상 — **나를 가리키는 자리에만** 쓴다(지금 상태 카드 · 나 머리 · 순위의 내 행 · 오목 플레이어 · 결과 · 위젯). 다른 사람은
/// `PersonAvatar`(사진 → 그 사람의 착용 캐릭터 얼굴 `PersonCharacterFace` → 이니셜 — 링·표정 없는 작은 얼굴). 오목 대국만 예외(맥처럼 양쪽 초상).
///
/// 표정 = 근무 상태(`CharacterMood`): 근무 중 웃음 + 초록 링·발광 · 연결 끊김 웃음 + 앰버 링 · 근무 안 함 시무룩 + 청회색 링 ·
/// `.plain` 은 링 없이 받침(surface2)만(상점 미리보기 · 고르기).
///
/// - `size`: 원 지름(pt). 탭 막대 25 · 행 32~40 · 카드 52 · 나 머리 68 · 무대 120~140. 192px 를 넘는 무대는 고해상 그림을 고른다.
/// - `ringGap`: 링과 그림 사이 틈의 색 = 초상이 놓인 면(카드 위면 기본 `surface`, 바탕 위면 `background`).
/// - `badge`: 오른쪽 아래 배지(편집 붓 · 오목 돌).
package struct CharacterPortrait: View {
    package enum Badge: Equatable, Sendable {
        case none
        /// accentFill 원 + SF 기호(예: "paintbrush.pointed.fill" — 캐릭터 바꾸기).
        case symbol(String)
        /// 오목 돌.
        case stone(isBlack: Bool)
    }

    private let id: String
    private let mood: CharacterMood
    private let size: CGFloat
    private let badge: Badge
    private let ringGap: Color
    private let framed: Bool
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - id: 착용 캐릭터 id(모르는 id·nil 은 아잉 — `AingCharacterArt.resolvedID`).
    ///   - framed: false 면 원·받침·링 없이 그림만(무대 카드의 큰 전신).
    package init(id: String?, mood: CharacterMood, size: CGFloat, badge: Badge = .none, ringGap: Color = MobileTheme.surface, framed: Bool = true) {
        self.id = AingCharacterArt.resolvedID(id)
        self.mood = mood
        self.size = size
        self.badge = badge
        self.ringGap = ringGap
        self.framed = framed
    }

    package var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if framed {
                framedArt
            } else {
                art(side: size)
            }
            badgeView
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var framedArt: some View {
        let ringWidth = CharacterMood.ringWidth(diameter: size)
        let ring = mood.ring.map(ringColor)
        return ZStack {
            Circle().fill(backing)
            if mood == .working {
                // 안쪽 발광(시안 inset 0 0 s*.25 rgba(47,196,126,.25)).
                Circle()
                    .strokeBorder(MobileTheme.workingDot.opacity(0.25), lineWidth: size * 0.18)
                    .blur(radius: size * 0.1)
                    .clipShape(Circle())
            }
            // 그림: 원 안 88%, 아래쪽으로 조금(시안 background-size 88% · 50% 62%).
            art(side: size * 0.88)
                .offset(y: size * 0.05)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay {
            if let ring {
                Circle()
                    .strokeBorder(ringGap, lineWidth: CharacterMood.ringGap)
                    .padding(-CharacterMood.ringGap)
                Circle()
                    .strokeBorder(ring, lineWidth: ringWidth)
                    .padding(-(CharacterMood.ringGap + ringWidth))
            }
        }
        .background {
            if mood == .working {
                Circle()
                    .fill(MobileTheme.workingDot.opacity(0.35))
                    .blur(radius: size * 0.15)
                    .padding(-size * 0.04)
            }
        }
    }

    private func art(side: CGFloat) -> some View {
        ArtImage(
            MobileArt.character(id: id, expression: mood.expression, pointSize: side, displayScale: displayScale),
            size: CGSize(width: side, height: side)
        )
    }

    private var backing: Color {
        switch mood {
        case .working: return MobileTheme.workingTint
        case .lost: return MobileTheme.pendingTint
        case .off: return MobileTheme.fill
        case .plain: return MobileTheme.surface2
        }
    }

    private func ringColor(_ status: PresenceStatus) -> Color {
        switch status {
        case .working: return MobileTheme.workingDot
        case .pending: return MobileTheme.pendingDot
        case .off: return MobileTheme.offWorkDot
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        switch badge {
        case .none:
            EmptyView()
        case .symbol(let name):
            let side = max(18, min(26, size * 0.32))
            Image(systemName: name)
                .font(.system(size: side * 0.5, weight: .bold))
                .foregroundStyle(MobileTheme.onAccentFill)
                .frame(width: side, height: side)
                .background(Circle().fill(MobileTheme.accentFill))
                .overlay(Circle().strokeBorder(ringGap, lineWidth: 2.5).padding(-2.5))
                .offset(x: 3, y: 3)
        case .stone(let isBlack):
            let side = max(12, min(20, size * 0.3))
            Circle()
                .fill(RadialGradient(
                    colors: isBlack ? [Color(white: 0.42), Color(white: 0.05)] : [Color.white, Color(white: 0.85)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: side * 0.7
                ))
                .frame(width: side, height: side)
                .overlay(Circle().strokeBorder(ringGap, lineWidth: 2).padding(-2))
                .offset(x: 2, y: 2)
        }
    }

    private var accessibilityText: String {
        let state: String
        switch mood {
        case .working: state = "근무 중"
        case .lost: state = "연결 끊김"
        case .off: state = "근무 안 함"
        case .plain: state = ""
        }
        return state.isEmpty ? "내 캐릭터" : "내 캐릭터, \(state)"
    }
}
#endif
