#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 지금 탭 화면 — **자리 파일**(탭 작업자가 통째로 소유한다). 경로는 `router.pathBinding(for: .now)`,
/// 딥링크는 `router.consumePendingRoute(for: .now)` 로 꺼낸다(`routeSerial` 이 바뀔 때마다).
struct NowTab: View {
    let store: NowStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .now)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        EmptyStateView(
                            systemImage: "clock.fill",
                            title: "지금 탭 준비 중",
                            message: "내 상태 카드 · 이번 주 목표 · 오늘 할 일 · 지금 근무 중"
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
            .navigationTitle("지금")
        }
        .onAppear { consumeRoute() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .now) {
            store.lastRoute = route
        }
    }
}
#endif
