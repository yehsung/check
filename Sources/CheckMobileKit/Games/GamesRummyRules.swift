#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 규칙 시트(설계서 §6 — 레인 C 가 이 파일을 채운다). 입력 없음(글자는 `GamesRummyText.rules`). 열고 닫는 값은 `store.rummy.rulesShown` — 화면이 쥔다.
struct GamesRummyRulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(GamesRummyText.rules, id: \.title) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.title).font(.headline)
                    Text(rule.detail).font(.subheadline).foregroundStyle(MobileTheme.label2)
                }
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
