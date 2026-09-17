import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 탭 스토어 · 푸시 코디네이터가 받는 **기반 묶음**(SPEC-ios-build §1-5). 모든 탭 스토어는 `init(context: MobileContext)` 하나로 만든다.
///
/// 쓰는 법(탭 작업자)
/// - 서버 호출: 세션 가드 → 세대 캡처 → `context.withMobileSessionRetry { session in try await context.service.… }` → 세대 가드.
///   `context.generation` 이 캡처 때와 다르면 응답을 버린다(로그아웃·계정 전환 뒤 늦게 온 응답).
/// - 시각: `context.clock.now()` 만(데모는 고정 시계, 테스트는 주입 시계).
/// - 딥링크: `context.router.open(.message(peerID:))` · 탭 경로 push 는 `context.router.push(_:on:)`.
/// - 위젯: 지금 탭만 `context.widgetSnapshots.update { $0.me = … }`.
/// - 실시간: `context.onMessageActivity { … }` · `context.onMessageRead { … }`(1초 합치기 — 등록 증표를 스토어가 쥔다).
///   오목 신호는 기반이 `context.gomoku.handleSignal()` 로 이미 배선했다.
/// - 다른 스토어·푸시: `context.links.messages` 등(약참조 — 앱 모델이 모두 만든 뒤 채운다. init 안에서는 아직 nil).
/// - **금지**: 서비스의 맥 전용 쓰기(iOS 에서 컴파일되지 않는다), `WorkTimerStore` 참조, 직접 `Date()`.
@MainActor
package struct MobileContext {
    package let service: SupabaseWorkService
    package let session: MobileSessionStore
    package let clock: MobileClock
    package let router: MobileRouter
    package let realtime: MobileRealtimeRunner
    package let widgetSnapshots: WidgetSnapshotWriter
    /// 코어 오목 스토어(host = `MobileGomokuHost`). 게임 탭이 화면을, 기반이 실시간 신호를 맡는다.
    package let gomoku: GomokuStore
    /// 오목 스토어의 호스트(루비 미러 `rubyBalance` 를 나 탭·게임 탭이 함께 읽는다).
    package let gomokuHost: MobileGomokuHost
    /// App Group 저장소(할 일 파일 `storage.todoFileURL(userID:)` · 공용 suite).
    package let storage: AingSharedStorage
    package let appInfo: MobileAppInfo
    /// 데모 모드인가(DEBUG 빌드의 `-AingCheckDemo YES`). 스토어는 이 값으로 동작을 바꾸지 않는다 — 스텁 서버가 다를 뿐이다.
    package let isDemo: Bool
    package let links: MobileStoreLinks

    package init(
        service: SupabaseWorkService,
        session: MobileSessionStore,
        clock: MobileClock,
        router: MobileRouter,
        realtime: MobileRealtimeRunner,
        widgetSnapshots: WidgetSnapshotWriter,
        gomoku: GomokuStore,
        gomokuHost: MobileGomokuHost,
        storage: AingSharedStorage,
        appInfo: MobileAppInfo,
        isDemo: Bool,
        links: MobileStoreLinks
    ) {
        self.service = service
        self.session = session
        self.clock = clock
        self.router = router
        self.realtime = realtime
        self.widgetSnapshots = widgetSnapshots
        self.gomoku = gomoku
        self.gomokuHost = gomokuHost
        self.storage = storage
        self.appInfo = appInfo
        self.isDemo = isDemo
        self.links = links
    }

    /// 지금 세션 세대. 응답 적용 전에 캡처값과 비교한다.
    package var generation: Int { session.generation }

    /// 401 → 조정자 경유 갱신 1회 → 재시도. 치명 실패만 로그아웃(`MobileSessionStore.withMobileSessionRetry`).
    package func withMobileSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        try await session.withMobileSessionRetry(operation)
    }

    /// 새 메시지 신호(`.drain`) · 조인 따라잡기(`.catchUp`) 핸들러.
    @discardableResult
    package func onMessageActivity(_ handler: @escaping @MainActor () -> Void) -> MobileRealtimeRegistration {
        realtime.onMessageActivity(handler)
    }

    /// 읽음 신호(`message_read`) 핸들러.
    @discardableResult
    package func onMessageRead(_ handler: @escaping @MainActor () -> Void) -> MobileRealtimeRegistration {
        realtime.onMessageRead(handler)
    }
}

/// 스토어끼리의 약참조 묶음. 앱 모델이 스토어를 모두 만든 **뒤** 채운다 — 스토어 init 안에서 읽으면 nil 이다.
/// 순환 참조를 만들지 않으려고 전부 weak 다(주인은 `MobileAppModel`).
@MainActor
package final class MobileStoreLinks {
    package weak var now: NowStore?
    package weak var messages: MessagesStore?
    package weak var rankings: RankingsStore?
    package weak var games: GamesStore?
    package weak var me: MeStore?
    package weak var push: PushCoordinator?

    package init() {}

    /// 탭 배지 합성(메시지 · 게임). 푸시 코디네이터의 앱 아이콘 배지도 이 값의 합이다.
    package var badges: MobileBadges {
        MobileBadges(messages: messages?.badgeCount ?? 0, games: games?.badgeCount ?? 0)
    }
}

/// 코어 `GomokuStore` 의 호스트를 폰 세션으로 구현한다(맥은 `WorkTimerStore` 가 같은 프로토콜에 적합하다).
@MainActor
@Observable
package final class MobileGomokuHost: GomokuStoreHost {
    @ObservationIgnored private let sessionStore: MobileSessionStore
    @ObservationIgnored private weak var realtimeRunner: MobileRealtimeRunner?
    /// 루비 잔액 미러. 오목 응답이 쓰고(정산), 나 탭 상점이 `shop_state` 로 채운다. nil = 모른다(막지 않는다 — 맥 0.3.29 규칙).
    package var rubyBalance: Int?

    package init(sessionStore: MobileSessionStore, realtime: MobileRealtimeRunner) {
        self.sessionStore = sessionStore
        self.realtimeRunner = realtime
    }

    package var session: SupabaseSession? { sessionStore.session }
    package var sessionGeneration: Int { sessionStore.generation }
    package var service: SupabaseWorkService { sessionStore.service }
    package var realtimeState: RealtimeState { realtimeRunner?.state ?? .idle(.disabled) }

    package func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        try await sessionStore.withMobileSessionRetry(operation)
    }

    package func classifyAuthError(_ error: Error) -> AuthErrorDisposition {
        AuthErrorRules.classify(error)
    }
}
