#if os(iOS)
import CheckMobileShared
import SwiftUI

/// 폰 앱의 루트 화면. 앱 타깃(`ios/App`)은 `MobileRootView(model:)` 하나만 본다.
///
/// 세션 단계로 가른다: 실행 중 → 업데이트 필요 → 로그인 → 탭 5개(지금 · 메시지 · 순위 · 게임 · 나, 배지 = 메시지·게임).
/// scenePhase 는 여기서 모델로 넘기고(active / background), 딥링크(`aingcheck://`)는 `onOpenURL` 로 라우터에 넘긴다.
public struct MobileRootView: View {
    private let model: MobileAppModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: MobileAppModel) {
        self.model = model
    }

    public var body: some View {
        content
            .tint(MobileTheme.accent)
            .onAppear {
                // 화면 모드는 앱 델리게이트가 창이 생기기 전에 걸었다 — 여기서 한 번 더(앱 타깃이 빠뜨려도 첫 화면에서 걸린다).
                model.installAppearance()
                model.start()
                applyScenePhase(scenePhase)
            }
            .onChange(of: scenePhase) { _, phase in
                applyScenePhase(phase)
            }
            .onOpenURL { url in
                model.handleOpenURL(url)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        // w15 기반: 부품 견본(데모 라우트 `components/…` — `MobileComponentsGallery`). Release 에는 이 갈래가 없다.
        if let route = model.environment.demoRoute, route.hasPrefix("components") {
            MobileComponentsGallery(route: route)
        } else {
            phases
        }
        #else
        phases
        #endif
    }

    @ViewBuilder
    private var phases: some View {
        switch model.session.phase {
        case .launching:
            MobileLaunchingView()
        case .needsUpdate(let minBuild):
            MobileUpdateRequiredView(minBuild: minBuild, currentBuild: model.session.appInfo.build)
        case .signedOut:
            MobileLoginView(session: model.session)
        case .signedIn:
            MobileTabsView(model: model)
        }
    }

    private func applyScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            model.sceneDidBecomeActive()
        case .background:
            model.sceneDidEnterBackground()
        case .inactive:
            // inactive(알림 센터 내리기 · 앱 전환 중)는 연결을 끊지 않는다 — 곧 active 로 돌아오는 일이 대부분이다.
            break
        @unknown default:
            break
        }
    }
}

/// 탭 막대. 각 탭 화면이 자기 NavigationStack 을 쥔다(경로는 라우터).
struct MobileTabsView: View {
    let model: MobileAppModel

    var body: some View {
        @Bindable var router = model.router
        let badges = model.badges
        TabView(selection: $router.selectedTab) {
            NowTab(store: model.now)
                .tabItem { Label(AingTab.now.title, systemImage: AingTab.now.systemImage) }
                .tag(AingTab.now)
            MessagesTab(store: model.messages)
                .tabItem { Label(AingTab.messages.title, systemImage: AingTab.messages.systemImage) }
                .badge(badges.badge(for: .messages) ?? 0)
                .tag(AingTab.messages)
            RankingsTab(store: model.rankings)
                .tabItem { Label(AingTab.rankings.title, systemImage: AingTab.rankings.systemImage) }
                .tag(AingTab.rankings)
            GamesTab(store: model.games)
                .tabItem { Label(AingTab.games.title, systemImage: AingTab.games.systemImage) }
                .badge(badges.badge(for: .games) ?? 0)
                .tag(AingTab.games)
            MeTab(store: model.me)
                .tabItem { Label(AingTab.me.title, systemImage: AingTab.me.systemImage) }
                .tag(AingTab.me)
        }
    }
}
#endif
