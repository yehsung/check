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
