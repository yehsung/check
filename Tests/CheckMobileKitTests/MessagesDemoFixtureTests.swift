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
    static let harin = "d0000000-0000-4000-8000-0000000000b5"
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
                await baseYield()
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
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음
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
        // 메시지 묶음은 최근순 그대로다(찌르기는 안 들어간다 — 코어 `MessageThreadBuilder`).
        #expect(demo.store.threads.map(\.peerName) == ["소라", "한결", "민재", "도윤"])
        #expect(demo.store.unreadPeerIDs == [Self.sora, Self.doyun])
        #expect(demo.store.badgeCount == 3)
        #expect(!demo.requests.contains { $0.rpcName == "mark_messages_read" })

        demo.store.loadDirectory()
        await demo.settle()
        // 화면이 그리는 줄은 찌르기를 포함한 **4단 정렬**이다 — 찌르기만 있는 하린이 맨 위에 선다(1.0.13).
        #expect(demo.store.threadItems(now: MobileClock.demoInstant).map(\.peerName)
            == ["하린", "소라", "도윤", "한결", "민재"])
        #expect(demo.store.directory.count == 8)
        let firstThreeWorking = demo.store.directory.prefix(3).filter { $0.isWorking }.count
        #expect(firstThreeWorking == 3)
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }


    @Test("찌르기 장면: 데모 스토어(앱 경로)를 지나 대화창에 찌르기 줄이 그려지고 · 찌르기만 있는 하린이 목록 맨 위에 선다")
    func pokeSceneGoesThroughTheStore() async {
        let demo = await Self.make(route: "messages")
        defer { demo.tearDown() }
        demo.store.listDidAppear()
        demo.store.loadDirectory()
        await demo.settle()

        // ① 스토어가 새 RPC 로 받았다(옛 조회가 아니다).
        #expect(demo.requests.contains { $0.rpcName == "message_history_with_pokes" })
        #expect(!demo.requests.contains { $0.rpcName == "message_history_with_reads" })
        #expect(demo.store.pokeLogAvailable)
        #expect(demo.store.pokeLog.count == 4)
        #expect(demo.store.unreadPokePeerIDs == [Self.harin], "하린의 안 본 찌르기를 못 셌다")
        #expect(demo.store.unreadPeerIDs == [Self.sora, Self.doyun], "찌르기가 메시지 안 읽음으로 샜다")

        // ② 목록: 찌르기만 있는 하린의 행이 서고, 네 무리가 다 선다.
        let rows = demo.store.threadItems(now: MobileClock.demoInstant)
        #expect(rows.map(\.peerName) == ["하린", "소라", "도윤", "한결", "민재"],
                "목록 순서: \(rows.map { "\($0.peerName)/\($0.group)" })")
        #expect(rows.map(\.group) == [0, 0, 1, 2, 3])
        #expect(rows[0].previewText == "하린님이 울트라 찔렀어요", "찌르기만 있는 행의 미리보기가 찌르기 문구가 아니다")
        #expect(rows[0].isUnread)
        #expect(rows[0].countBadge == nil, "안 읽음이 찌르기뿐인데 '안 읽은 메시지' 숫자가 섰다")
        #expect(rows[1].countBadge == "2")
        #expect(rows[3].previewText == "내가 울트라 찔렀어요", "한결 행 미리보기가 마지막 활동(내 울트라)이 아니다")

        // ③ 대화창: 한결에게 받은 콕 하나 + 내가 보낸 울트라 하나가 말풍선 사이에 낀다.
        let items = demo.store.conversationItems(for: Self.hangyeol)
        let pokeLines = items.compactMap { item -> String? in
            if case .poke(let line) = item { return line.text } else { return nil }
        }
        #expect(pokeLines == ["한결님이 콕 찔렀어요 · 11:39", "내가 울트라 찔렀어요 · 13:53"],
                "대화창에 찌르기 줄이 안 그려졌다")
        let ids = items.map(\.id)
        let pokeIndex = ids.firstIndex(of: "poke-d0000000-0000-4000-8000-00000000f001")
        let nextBubble = pokeIndex.flatMap { index in ids[(index + 1)...].first { !$0.hasPrefix("poke-") && !$0.hasPrefix("day-") } }
        #expect(nextBubble == "d0000000-0000-4000-8000-00000000e005", "찌르기 줄이 11:39 와 11:40 사이에 안 들어갔다")

        // ④ 찌르기만 있는 사람의 대화창도 그 줄만으로 선다.
        let harinItems = demo.store.conversationItems(for: Self.harin)
        #expect(harinItems.compactMap { item -> String? in
            if case .poke(let line) = item { return line.text } else { return nil }
        } == ["하린님이 콕 찔렀어요 · 14:00", "하린님이 울트라 찔렀어요 · 14:03"])
        #expect(demo.store.peerName(for: Self.harin) == "하린")
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
        #expect(!MessagesDemoLaunch.forcesNewMessageButton(isDemo: false, arguments: ["app", "-AingCheckDemoMessages", "newbutton"]))
        #expect(MessagesDemoLaunch.forcesNewMessageButton(isDemo: true, arguments: ["app", "-AingCheckDemoMessages", "newbutton"]))
        #expect(!MessagesDemoLaunch.forcesNewMessageButton(isDemo: true, arguments: ["app", "-AingCheckDemoMessages", "new"]))
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }

    @Test("이력 실패 장면(c1): 이력 500 · 사람 찾기 없음 → 실패 화면과 다시 시도 · 머리는 '대화' + 이니셜 없음 · 보이스오버 '이름을 불러오지 못한 대화' · 금지 호출 0")
    func historyFailureScene() async {
        let peer = "d0000000-0000-4000-8000-0000000000c1"
        let demo = await Self.make(route: "messages/\(peer)")
        defer { demo.tearDown() }
        demo.store.conversationDidAppear(peerID: peer, token: UUID())
        await demo.settle()
        #expect(demo.store.historyFailed)
        #expect(!demo.store.historyLoaded)
        #expect(MessagesConversationRules.emptyState(loaded: demo.store.historyLoaded, failed: demo.store.historyFailed).showsRetry)
        #expect(demo.store.peerName(for: peer) == nil)
        let header = demo.store.conversationHeader(for: peer)
        #expect(header.title == "대화")
        #expect(header.avatarName == nil)
        #expect(header.accessibilityLabel == MessagesConversationHeader.unknownAccessibilityLabel)
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }
}
