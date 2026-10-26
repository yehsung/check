#if os(iOS)
import CheckCore
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
            // 스크롤한 내용이 접힌 내비 머리 뒤로 비치지 않게 — 앱 전체에 한 번 건다(스크롤 뷰로 내려간다).
            .opaqueNavigationEdge()
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
            // w16: 데모 라우트 `signup` · `signup/create` · `reset` 은 로그인 아래 화면을 바로 연다(앱스토어 스크린샷). 실제 실행은 nil.
            MobileLoginView(session: model.session, initialRoute: MobileAuthRoute.demo(model.environment.demoRoute))
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
///
/// '나' 탭 기호만 SF 기호가 아니라 **착용 캐릭터 초상 + 근무 상태 링**이다(시안 b2 — "나 = 착용 캐릭터"가 탭 막대에서도 보인다).
/// 그림이 없는 빌드(리소스 누락)에서는 SF 기호로 접는다.
struct MobileTabsView: View {
    let model: MobileAppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

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
                .tabItem { meLabel }
                // 받을 보상 수(도전 미션 + 이번 주 근무 단계 — v0.3.58). 앱 아이콘 배지에는 더하지 않는다(`appBadgeTotal`).
                .badge(badges.badge(for: .me) ?? 0)
                .tag(AingTab.me)
        }
        // 사람 아바타(사진 → 착용 캐릭터 → 이니셜)가 찾는 캐릭터 한 표 — 탭 다섯과 그 위에 뜨는 시트가 모두 이어받는다.
        .environment(\.appUserCharacters, model.characters.directory)
        // 탭을 바꿀 때 표를 60초 스로틀로 다시 묻는다(새 폴링 없음 — 기존 갱신 시점에 얹는다).
        .onChange(of: router.selectedTab) { _, _ in
            model.tabDidChange()
        }
        // 생일 선물 축하 시트(v0.3.66 · 폰 1.0.14) — 탭 막대 위에서 띄워 어느 탭에 있든 뜬다. 상태는 나 탭 스토어가 쥔다
        // (`MeStoreCakeGift.swift` — 실행당 한 번 · 닫으면 나 탭 '다시 열기' 줄).
        .sheet(item: cakeGiftSheet) { _ in
            MeCakeGiftSheetView(store: model.me)
        }
        // 못 띄운 시트 거두기: 스토어가 시트를 세웠는데 2초 안에 화면에 안 섰으면(다른 시트 · 덮개가 떠 있어 SwiftUI 가 조용히 못 띄웠다 ·
        // 알림 설명 시트가 떠 있다) 닫은 것으로 친다 — 그러면 나 탭 '다시 열기' 줄이 서서 수령 길이 막히지 않는다(실행당 한 번은 쓴 것이다).
        .task(id: model.me.cakeGiftSheet?.id) {
            guard model.me.cakeGiftSheet != nil, !model.me.cakeGiftSheetOnScreen else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, model.me.cakeGiftSheet != nil, !model.me.cakeGiftSheetOnScreen else { return }
            model.me.dismissCakeGiftSheet()
        }
    }

    /// 축하 시트 바인딩. **아직 화면에 서기 전에만** 알림 설명 시트(UIKit — `PushNotificationCenterAdapter`)를 피한다 — 같은 화면이 이미
    /// 무엇을 띄우고 있으면 SwiftUI 시트는 조용히 안 뜬다. 이미 서 있으면 설명 시트가 위에 올라와도 내리지 않는다.
    private var cakeGiftSheet: Binding<MeCakeGiftSheet?> {
        Binding(
            get: {
                guard let sheet = model.me.cakeGiftSheet else { return nil }
                if model.me.cakeGiftSheetOnScreen { return sheet }
                guard !model.push.isPrimerPresented else { return nil }
                #if DEBUG
                // 데모 `me/gift/dismissed`: 띄우지 않는다 — 위 거두기가 닫은 것으로 쳐 나 탭 '다시 열기' 줄이 선다(스크린샷).
                if MeDemoHooks.cakeGiftAction() == "dismissed" { return nil }
                #endif
                return sheet
            },
            set: { value in
                if value == nil { model.me.dismissCakeGiftSheet() }
            }
        )
    }

    /// '나' 탭 이름 + 초상 기호. 착용 캐릭터·근무 상태·화면 모드가 바뀌면 이 본문이 다시 돌아 새 이미지를 받는다
    /// (`displayedCharacterID`·`displayedMood` 는 관찰되는 값이라 스토어가 바뀌면 탭 막대도 따라 바뀐다).
    @ViewBuilder
    private var meLabel: some View {
        if let icon = CharacterTabIcon.image(
            id: model.now.displayedCharacterID,
            mood: model.now.displayedMood,
            isDark: colorScheme == .dark,
            scale: displayScale
        ) {
            Label { Text(AingTab.me.title) } icon: { Image(uiImage: icon) }
        } else {
            Label(AingTab.me.title, systemImage: AingTab.me.systemImage)
        }
    }
}
#endif
