import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 메시지 탭 데모 픽스처(`Demo/Fixtures/messages/**`)가 **실제 서비스 디코드 → 스토어**를 지나 스크린샷 장면을 만드는지.
///
/// 데모 조립(`MobileDemo.environment`)은 전역 호스트 하나를 쓰므로(기반 테스트와 병렬로 부딪친다) 여기서는 같은 픽스처 색인을
/// **고유 호스트**에 물려 앱 모델을 세운다 — 응답 규칙(`MobileDemoFixtures.response(for:scenario:)`)은 데모와 같은 함수다.
@MainActor
@Suite(.serialized) struct MessagesDemoFixtureTests {
    static let hangyeol = "d0000000-0000-4000-8000-0000000000b1"
    static let sora = "d0000000-0000-4000-8000-0000000000b2"
    static let minjae = "d0000000-0000-4000-8000-0000000000b3"
    static let doyun = "d0000000-0000-4000-8000-0000000000b4"
    static let jiwoo = "d0000000-0000-4000-8000-0000000000b9"

    @MainActor
    struct Demo {
        let host: String
        let storage: AingSharedStorage
        let model: MobileAppModel
        var store: MessagesStore { model.messages }
        var requests: [MobileStubRequest] { MobileStubURLProtocol.requests(host: host) }
        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }

        func settle() async {
            for _ in 0..<3 {
                _ = await baseWaitUntil { store.pendingActivityTask == nil && !store.isMarkingRead && !store.isSending && !store.directoryLoading }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    static func make(route: String) async -> Demo {
        let host = BaseStub.makeHost("messages-demo")
        let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
        let index = MobileDemoFixtures.load()
        MobileStubURLProtocol.register(host: host) { index.response(for: $0, scenario: scenario) }
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
        vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: vault,
            storage: storage,
            appInfo: MobileAppInfo(build: 1, version: "0.1.0", osVersion: "iOS 18.0", apnsEnvironment: nil),
            clock: .fixed(MobileClock.demoInstant),
            installationID: MobileDemo.installationID,
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {},
            demoRoute: route
        )
        let model = MobileAppModel(environment: environment)
        model.messages.postMarkRefreshSeconds = 3600
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedIn }
        model.sceneDidBecomeActive()
        let demo = Demo(host: host, storage: storage, model: model)
        await demo.settle()
        return demo
    }

    @Test("목록 장면: 대화 4개(최근순) · 안 읽음 소라·도윤 · 배지 3 · 오늘/어제 줄 · 읽음 올리지 않음 · 금지 호출 0")
    func listScene() async {
        let demo = await Self.make(route: "messages")
        defer { demo.tearDown() }
        #expect(demo.model.router.selectedTab == .messages)
        #expect(demo.model.router.consumePendingRoute(for: .messages) == .messages)
        #expect(demo.store.badgeCount == 3)
        demo.store.listDidAppear()
        await demo.settle()
        #expect(demo.store.readReceiptsAvailable)
        #expect(demo.store.threads.map(\.peerName) == ["소라", "한결", "민재", "도윤"])
        #expect(demo.store.unreadPeerIDs == [Self.sora, Self.doyun])
        #expect(demo.store.badgeCount == 3)
        #expect(!demo.requests.contains { $0.rpcName == "mark_messages_read" })

        demo.store.loadDirectory()
        await demo.settle()
        #expect(demo.store.directory.count == 8)
        let firstThreeWorking = demo.store.directory.prefix(3).filter { $0.isWorking }.count
        #expect(firstThreeWorking == 3)
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("대화 장면(한결): 어제·오늘 구분선 · 내 말 두 개에 1 · 같은 분은 마지막에만 시각 · 안 읽은 말이 없어 읽음 0 · 금지 호출 0")
    func conversationScene() async {
        let demo = await Self.make(route: "messages/\(Self.hangyeol)")
        defer { demo.tearDown() }
        #expect(demo.model.router.consumePendingRoute(for: .messages) == .message(peerID: Self.hangyeol))
        demo.store.conversationDidAppear(peerID: Self.hangyeol, token: UUID())
        await demo.settle()
        let items = demo.store.conversationItems(for: Self.hangyeol)
        let days = items.compactMap { item -> String? in if case .day(_, let label) = item { return label } else { return nil } }
        #expect(days == ["어제", "오늘"])
        let lines = items.compactMap { item -> MessagesBubbleLine? in if case .bubble(let line) = item { return line } else { return nil } }
        #expect(lines.count == 7)
        let unreadOnes = lines.filter { $0.showsUnreadOne }.count
        let lastTwoTimes = lines.suffix(2).map { $0.showsTime }
        #expect(unreadOnes == 2)
        #expect(lastTwoTimes == [false, true])
        #expect(demo.store.peerName(for: Self.hangyeol) == "한결")
        #expect(!demo.requests.contains { $0.rpcName == "mark_messages_read" })
        #expect(demo.model.router.visibleConversationPeerID == Self.hangyeol)
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("입력칸 장면(민재): 185자 보내기 → 장면 픽스처가 target_focused → 글이 돌아오고 카운터·집중 문구 · 금지 호출 0")
    func composerScene() async {
        let demo = await Self.make(route: "messages/\(Self.minjae)")
        defer { demo.tearDown() }
        demo.store.conversationDidAppear(peerID: Self.minjae, token: UUID())
        await demo.settle()
        MessagesDemoLaunch.seedComposerIfRequested(store: demo.store, peerID: Self.minjae,
                                                   arguments: ["app", "-AingCheckDemoMessages", "composer"])
        await demo.settle()
        #expect(demo.store.sendNotices[Self.minjae] == MessageNoticeText.targetFocused)
        #expect(demo.store.draft(for: Self.minjae) == MessagesDemoLaunch.composerDraft)
        #expect(MessagesComposerRules.counterText(for: demo.store.draft(for: Self.minjae)) != nil)
        #expect(demo.store.pendingOutgoing.isEmpty)
        // 다시 불러도(뷰가 다시 설 때) 두 번 보내지 않는다.
        MessagesDemoLaunch.seedComposerIfRequested(store: demo.store, peerID: Self.minjae,
                                                   arguments: ["app", "-AingCheckDemoMessages", "composer"])
        await demo.settle()
        #expect(demo.requests.filter { $0.rpcName == "send_message" }.count == 1)
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("빈 대화 장면(지우): 이력 없음 → 사람 찾기 목록으로 이름을 채운다 · 데모 고리는 데모가 아니면 꺼져 있다")
    func emptyConversationScene() async {
        let demo = await Self.make(route: "messages/\(Self.jiwoo)")
        defer { demo.tearDown() }
        demo.store.conversationDidAppear(peerID: Self.jiwoo, token: UUID())
        await demo.settle()
        #expect(demo.store.conversationItems(for: Self.jiwoo).isEmpty)
        #expect(demo.store.peerName(for: Self.jiwoo) == "지우")
        #expect(MessagesConversationRules.emptyState(loaded: demo.store.historyLoaded, failed: demo.store.historyFailed).title == "아직 주고받은 메시지가 없어요")
        #expect(!MessagesDemoLaunch.opensNewConversation(isDemo: false, arguments: ["app", "-AingCheckDemoMessages", "new"]))
        #expect(MessagesDemoLaunch.opensNewConversation(isDemo: true, arguments: ["app", "-AingCheckDemoMessages", "new"]))
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }
}
