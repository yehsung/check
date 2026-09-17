import CheckCore
import CheckMobileShared
import Foundation

/// 앱 모델을 조립하는 재료(서비스 · 금고 · 저장소 · 시계 · 소켓 · 위젯 새로고침). 프로덕션은 `live()`, 데모는 `MobileDemo`,
/// 테스트는 스텁 서비스·메모리 금고·임시 저장소로 직접 만든다.
@MainActor
package struct MobileEnvironment {
    package var service: SupabaseWorkService
    package var vault: TokenVault
    package var storage: AingSharedStorage
    package var appInfo: MobileAppInfo
    package var clock: MobileClock
    package var installationID: String
    /// nil = 실시간 없음(테스트·데모·킬스위치). 링은 `.idle(.disabled)` 로 태어나 움직이지 않는다.
    package var realtimeTransport: RealtimeTransport?
    /// 벽시계 타이머(실시간 틱·토큰 선제 갱신)를 띄울지. 테스트는 false.
    package var runsTimers: Bool
    package var reloadWidgetTimelines: @MainActor () -> Void
    /// 데모 실행이면 시작 라우트(`-AingCheckDemoRoute`). nil = 실제 서버.
    package var demoRoute: String?

    package init(
        service: SupabaseWorkService,
        vault: TokenVault,
        storage: AingSharedStorage,
        appInfo: MobileAppInfo,
        clock: MobileClock,
        installationID: String,
        realtimeTransport: RealtimeTransport?,
        runsTimers: Bool,
        reloadWidgetTimelines: @escaping @MainActor () -> Void,
        demoRoute: String? = nil
    ) {
        self.service = service
        self.vault = vault
        self.storage = storage
        self.appInfo = appInfo
        self.clock = clock
        self.installationID = installationID
        self.realtimeTransport = realtimeTransport
        self.runsTimers = runsTimers
        self.reloadWidgetTimelines = reloadWidgetTimelines
        self.demoRoute = demoRoute
    }

    package var isDemo: Bool { demoRoute != nil }

    /// 프로덕션 조립: 번들 `CheckConfig.plist` 의 anon 키 · 공유 키체인 · App Group · 실소켓(킬스위치 존중).
    package static func live(bundle: Bundle = .main) -> MobileEnvironment {
        let vault = KeychainTokenVault(service: AingKeychain.service, accessGroup: AingKeychain.accessGroup)
        let storage = AingSharedStorage.live()
        storage.ensureDirectory()
        return MobileEnvironment(
            service: SupabaseWorkService(anonKey: SupabaseConfig.anonKey(bundle: bundle)),
            vault: vault,
            storage: storage,
            appInfo: .fromBundle(bundle),
            clock: .system,
            installationID: InstallationID.current(store: vault),
            realtimeTransport: RealtimeFeature.isEnabled(defaults: storage.defaults) ? LiveRealtimeTransport() : nil,
            runsTimers: true,
            reloadWidgetTimelines: MobileWidgetTimelines.reloadAll
        )
    }
}

extension KeychainTokenVault: AingSecretStore {}
extension InMemoryTokenVault: AingSecretStore {}
