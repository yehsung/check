#if os(iOS)
import SwiftUI

// 시트 머리 규칙(비평 "시트": 닫기 위치가 시트마다 왼쪽·오른쪽으로 갈리고 판돈 시트는 닫는 길이 둘이었다).
// **닫기는 왼쪽 위 유리 원형 ✕ 하나**(iOS 시트 관례 — 확인 동작이 있으면 오른쪽). 아래에 '취소' 버튼을 또 두지 않는다.

package enum SheetChromeText {
    package static let close = "닫기"
}

/// 내비게이션 스택이 없는 시트의 머리: [✕] 가운데 제목(+ 부제) [오른쪽 선택 동작].
package struct SheetHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let onClose: () -> Void
    private let trailing: Trailing

    package init(_ title: String, subtitle: String? = nil, onClose: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.trailing = trailing()
    }

    package var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MobileTheme.label2)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, AingButtonMetrics.minimumTarget + MobileTheme.space3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack {
                GlassCircleButton(systemImage: "xmark", accessibilityLabel: SheetChromeText.close, action: onClose)
                Spacer(minLength: 0)
                trailing
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space3)
        .padding(.bottom, MobileTheme.space2)
    }
}

extension SheetHeader where Trailing == EmptyView {
    package init(_ title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.init(title, subtitle: subtitle, onClose: onClose) { EmptyView() }
    }
}

// MARK: - 위험한 동작 확인

/// 위험한 동작 확인(기권 · 삭제)을 **불투명 시트**로 묻는다.
///
/// 시스템 알림창(`.alert`)을 쓰지 않는 이유(w15 검증 medium 1 · 실측): 알림창 재질이 뒤 화면 색을 빨아들여 오목 나무판 위에서
/// 크림색(#D0BEA4)이 되고, 그 위 시스템 빨강 글자가 **1.9:1**(라이트) · 2.8:1(다크)까지 떨어졌다. 버튼 글자도 앱 토큰(`danger`)이
/// 아니라 시스템 빨강이라 색 뜻 규칙 밖이었다. 시트는 `presentationBackground` 로 카드 색을 불투명하게 깔 수 있어 뒤 화면과 무관하게
/// dangerTint 위 danger(4.5:1)가 보장된다.
///
/// 버튼 두 개는 세로로 쌓는다(큰 글자에서 가로 두 칸은 글자가 두 줄로 접힌다). 위가 위험한 동작(`.destructive`), 아래가 취소(`.gray`).
package struct AingConfirmSheet: View {
    private let title: String
    private let message: String?
    private let confirmTitle: String
    private let cancelTitle: String
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    @State private var measured: CGFloat = 200

    package init(
        title: String,
        message: String? = nil,
        confirmTitle: String,
        cancelTitle: String,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    package var body: some View {
        VStack(spacing: MobileTheme.space3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MobileTheme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AingButton(confirmTitle, kind: .destructive, fillsWidth: true, action: onConfirm)
                .padding(.top, MobileTheme.space1)
            AingButton(cancelTitle, kind: .gray, fillsWidth: true, action: onCancel)
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space4)
        .padding(.bottom, MobileTheme.space4)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ConfirmSheetHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(ConfirmSheetHeightKey.self) { height in
            // 큰 글자에서 글이 접히면 시트도 그만큼 높아진다(고정 높이면 버튼이 잘린다).
            if height > 0 { measured = height }
        }
        .presentationDetents([.height(measured)])
        .presentationBackground(MobileTheme.surface)
        .presentationDragIndicator(.visible)
    }
}

private struct ConfirmSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// `NavigationStack` 안 시트의 닫기: 왼쪽 위(`cancellationAction`) 유리 ✕ — `SheetHeader` 와 같은 자리·모양.
    package func sheetCloseButton(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: action) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MobileTheme.label)
                }
                .accessibilityLabel(Text(SheetChromeText.close))
            }
        }
    }
}

// MARK: - 내비 머리

extension View {
    /// 스크롤한 내용이 **접힌 내비 머리 뒤로 비치지 않게** 한다 — 스크롤 뷰에 건다.
    ///
    /// 실측 결함(w15 검증 medium 5 · 낮음 4): iOS 26 기본 머리는 가장자리 효과가 물러서 제목·부제 뒤로 내용이 또렷하게 읽혔다.
    /// 오목 로비에서는 부제 '한 수 30초'가 밑으로 지나가는 파랑 [수락] 버튼 위에 얹혀 4.0:1 로 떨어졌고, 지금·설정·제보에서는
    /// 할 일 한 줄이 제목 옆에 그대로 겹쳐 보였다. `.hard` 는 머리 아래를 불투명하게 끊는다(시안 b2 의 머리도 불투명이다).
    /// iOS 18 에는 그 효과가 없어 `toolbarBackground(.visible)` 로 접는다.
    package func opaqueNavigationEdge() -> some View {
        modifier(AingHardScrollEdge())
    }
}

private struct AingHardScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26 에서는 `toolbarBackground(.visible)` 이 더해도 달라지지 않는다(실측: 같은 픽셀) — 가장자리 효과가 주인이다.
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content.toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - 탭 막대 숨김

extension View {
    /// 이 화면이 떠 있는 동안 탭 막대를 숨긴다. **내비게이션 목적지(push 된 화면)의 루트 뷰**에 건다 — 탭 루트에 걸면 탭 막대가 통째로 사라진다.
    ///
    ///     GomokuMatchScreen(…)
    ///         .hidesTabBar(for: .gomokuMatch)
    ///
    /// 실체는 `.toolbar(.hidden, for: .tabBar)` 한 줄이다(뒤로 가면 시스템이 되살린다). 공용 수단으로 둔 이유는 숨기는 화면 목록을
    /// 한 곳에서 말하기 위해서다. 시뮬레이터 실측(w15 기반 부품 견본 `components/tabbar`): push 하면 숨고, 그 화면에서 시트를 띄웠다
    /// 닫아도 숨은 채이고, 뒤로 가면 다시 보인다.
    package func hidesTabBar(for screen: TabBarPolicy.Screen) -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
#endif
