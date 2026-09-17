#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 순위 탭 화면 — **자리 파일**(탭 작업자가 통째로 소유한다). 경로는 `router.pathBinding(for: .rankings)`,
/// 딥링크는 `router.consumePendingRoute(for: .rankings)` 로 꺼낸다(`routeSerial` 이 바뀔 때마다).
struct RankingsTab: View {
    let store: RankingsStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .rankings)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        EmptyStateView(
                            systemImage: "trophy.fill",
                            title: "순위 탭 준비 중",
                            message: "팀 리그 · AI 토큰 · 미니게임"
                        )
                    }
                    if let route = store.lastRoute {
                        InlineNotice(text: "열린 링크 · \(route.url.absoluteString)", kind: .info)
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle("순위")
        }
        .onAppear { consumeRoute() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .rankings) {
            store.lastRoute = route
        }
    }
}
#endif
