#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 나 탭 화면 — **자리 파일**(탭 작업자가 통째로 소유한다). 경로는 `router.pathBinding(for: .me)`,
/// 딥링크는 `router.consumePendingRoute(for: .me)` 로 꺼낸다(`routeSerial` 이 바뀔 때마다).
struct MeTab: View {
    let store: MeStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .me)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        EmptyStateView(
                            systemImage: "person.crop.circle.fill",
                            title: "나 탭 준비 중",
                            message: "기록 · 캐릭터 · 프로필 · 제보 · 설정"
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
            .navigationTitle("나")
        }
        .onAppear { consumeRoute() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .me) {
            store.lastRoute = route
        }
    }
}
#endif
