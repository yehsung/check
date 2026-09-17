#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 메시지 탭 화면 — **자리 파일**(탭 작업자가 통째로 소유한다). 경로는 `router.pathBinding(for: .messages)`,
/// 딥링크는 `router.consumePendingRoute(for: .messages)` 로 꺼낸다(`routeSerial` 이 바뀔 때마다).
struct MessagesTab: View {
    let store: MessagesStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .messages)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        EmptyStateView(
                            systemImage: "bubble.left.and.bubble.right.fill",
                            title: "메시지 탭 준비 중",
                            message: "대화 목록 · 새 대화 · 대화 · 읽음 표시 · 24시간이 지난 메시지는 사라져요"
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
            .navigationTitle("메시지")
        }
        .onAppear { consumeRoute() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .messages) {
            store.lastRoute = route
        }
    }
}
#endif
