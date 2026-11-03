#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 규칙 시트(설계서 §6, 맥 `RummyRulesOverlay` 와 같은 내용을 터치로 다시 쓴 것). 입력 없음(글자·예시는 `GamesRummyText.rules`). 열고 닫는 값은 `store.rummy.rulesShown` — 화면이 쥔다.
struct GamesRummyRulesView: View {
    @Environment(\.dismiss) private var dismiss

    private static let tile = CGSize(width: 30, height: 41)

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GamesRummyText.rulesTitle, onClose: { dismiss() })
            ScrollView {
                InsetGroup {
                    ForEach(Array(GamesRummyText.rules.enumerated()), id: \.offset) { index, rule in
                        GroupRow(divider: index == GamesRummyText.rules.count - 1 ? .none : .inset(MobileTheme.cardPadding)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(rule.title)
                                    .font(MobileTheme.rowTitle)
                                    .foregroundStyle(MobileTheme.accent)
                                Text(rule.detail)
                                    .font(MobileTheme.rowSubtitle)
                                    .foregroundStyle(MobileTheme.label2)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !rule.example.isEmpty {
                                    HStack(spacing: 3) {
                                        ForEach(Array(rule.example.enumerated()), id: \.offset) { _, text in
                                            if let face = RummyFace(text: text) {
                                                GamesRummyTile(face: face, size: Self.tile)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, MobileTheme.space6)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
    }
}
#endif
