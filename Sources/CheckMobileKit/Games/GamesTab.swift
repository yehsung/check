#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 게임 탭 화면 — **자리 파일**(탭 작업자가 통째로 소유한다). 경로는 `router.pathBinding(for: .games)`,
/// 딥링크는 `router.consumePendingRoute(for: .games)` 로 꺼낸다(`routeSerial` 이 바뀔 때마다).
struct GamesTab: View {
    let store: GamesStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .games)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        EmptyStateView(
                            systemImage: "gamecontroller.fill",
                            title: "게임 탭 준비 중",
                            message: "타이밍 바 · 플래피 아잉 · 1:1 오목"
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
            .navigationTitle("게임")
        }
        .onAppear { consumeRoute() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .games) {
            store.lastRoute = route
        }
    }
}
#endif
