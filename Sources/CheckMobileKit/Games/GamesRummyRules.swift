#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 규칙 시트(설계서 §6, 맥 `RummyRulesOverlay` 와 같은 내용을 터치로 다시 쓴 것). 입력 없음(글자·예시는 `GamesRummyText.rules`). 열고 닫는 값은 `store.rummy.rulesShown` — 화면이 쥔다.
struct GamesRummyRulesView: View {
    @Environment(\.dismiss) private var dismiss

    private static let tile = CGSize(width: 30, height: 41)

    var body: some View {
        NavigationStack {
            List(GamesRummyText.rules, id: \.title) { rule in
                VStack(alignment: .leading, spacing: 6) {
                    Text(rule.title)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.accent)
                    Text(rule.detail)
                        .font(.subheadline)
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
                .padding(.vertical, 2)
            }
            .navigationTitle(GamesRummyText.rulesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(GamesRummyText.close) { dismiss() }
                }
            }
        }
    }
}
#endif
