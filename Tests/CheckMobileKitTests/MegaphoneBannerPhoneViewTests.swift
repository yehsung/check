import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 확성기 배너 · 폰 뷰(계약 docs/plan/megaphone-banner-contract.md — 폰 배너)
//
// 뷰(`MegaphoneBannerOverlay`)는 iOS 전용이라 맥 스위트가 컴파일하지 않는다. 그래서 둘로 잰다:
// ① 주석을 걷은 소스에서 **부르는 자리**(오버레이가 붙는 곳 · 손짓이 부르는 함수 · [답장]이 부르는 함수),
// ② 그 자리가 부르는 순수 판정·앱 모델 배선을 실제로 돌려서. 시험마다 결과를 가르는 기준선을 하나씩 둔다.

/// 시트 탐지기를 바꿔 끼우는 스위치.
@MainActor
final class MegaphoneModalSwitch {
    var on = false
}

@MainActor
@Suite(.serialized) struct MegaphoneBannerPhoneViewTests {
    nonisolated static let rootPath = "Sources/CheckMobileKit/App/MobileRootView.swift"
    nonisolated static let overlayPath = "Sources/CheckMobileKit/Messages/MegaphoneBannerOverlay.swift"
    nonisolated static let modelPath = "Sources/CheckMobileKit/App/MobileAppModel+MegaphoneBanner.swift"

    /// 공백을 모두 걷는다(줄바꿈·들여쓰기에 흔들리지 않게).
    static func squashed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    static func offset(of needle: String, in code: String) throws -> Int {
        let range = try #require(code.range(of: needle), "없다: \(needle)")
        return code.distance(from: code.startIndex, to: range.lowerBound)
    }

    // MARK: 자리

    @Test("오버레이 자리: TabView 에 .overlay(alignment: .top) 한 곳 · 캐릭터 표 환경값보다 안쪽 · 세이프에어리어 아래 · 좌우 sideMargin")
    func overlayPlacement() throws {
        let root = Self.squashed(try IntegrationContractTests.code(Self.rootPath))
        let mount = ".overlay(alignment:.top){MegaphoneBannerOverlay(model:model)}"
        let tabView = try Self.offset(of: "TabView(selection:$router.selectedTab)", in: root)
        let overlay = try Self.offset(of: mount, in: root)
        let characters = try Self.offset(of: ".environment(\\.appUserCharacters,model.characters.directory)", in: root)
        #expect(tabView < overlay, "배너가 탭 막대 밖(앞)에 붙었다")
        // 기준선: 환경값보다 바깥에 걸면 배너 아바타가 캐릭터 표를 못 받는다 — 순서가 결과를 가른다.
        #expect(overlay < characters, "배너가 캐릭터 표 환경값 바깥에 붙었다 — 아바타가 착용 캐릭터를 못 찾는다")
        #expect(root.components(separatedBy: "MegaphoneBannerOverlay(").count - 1 == 1, "루트에 배너가 하나가 아니다")
        // 부르는 자리는 루트 하나뿐 — 탭 하나(예: 메시지 탭)에 붙이면 다른 탭에서는 안 뜬다.
        let mounts = try IntegrationContractTests.files(containing: ["MegaphoneBannerOverlay(model:"], under: "Sources/CheckMobileKit")
        #expect(mounts == [Self.rootPath], "배너를 붙인 곳: \(mounts)")

        let overlayCode = Self.squashed(try IntegrationContractTests.code(Self.overlayPath))
        #expect(!overlayCode.contains("ignoresSafeArea"), "배너가 세이프에어리어를 무시한다 — 상태바·다이내믹 아일랜드를 덮는다")
        #expect(overlayCode.contains(".padding(.horizontal,MobileTheme.sideMargin)"))
        #expect(overlayCode.contains(".background(GlassBackground(shape:RoundedRectangle(cornerRadius:MegaphoneBannerPhoneRules.cornerRadius"))
        #expect(overlayCode.contains(".lineLimit(MegaphoneBannerPhoneRules.bodyLineLimit)"))
        #expect(MegaphoneBannerPhoneRules.bodyLineLimit == 4)
        #expect(overlayCode.contains("Text(MegaphoneText.icon)") && overlayCode.contains("PersonAvatar(name:banner.senderName"))
    }

    // MARK: 손

    @Test("카드만 hit-test: 화면 가득한 틀·바탕 없음 · 손짓은 카드에 simultaneousGesture(버튼 탭과 함께) · 기준선: 본문 폭 틀 하나만")
    func cardOnlyHitTesting() throws {
        let code = Self.squashed(try IntegrationContractTests.code(Self.overlayPath))
        #expect(!code.contains("maxHeight:.infinity"), "배너 틀이 화면 높이를 채운다 — 아래 게임 캔버스의 손을 먹는다")
        for blocker in ["Color.clear", "Rectangle().fill", ".highPriorityGesture(", ".gesture(", ".allowsHitTesting(true)"] {
            #expect(!code.contains(blocker), "카드 밖까지 손을 받거나 버튼 탭을 막는다: \(blocker)")
        }
        // 기준선: `.frame(` 은 본문 줄 폭 하나뿐이다(가로만 · 세로 무한 없음). 두 번째가 생기면 그것이 틀을 키운다.
        #expect(code.components(separatedBy: ".frame(").count - 1 == 1)
        #expect(code.contains(".frame(maxWidth:.infinity,alignment:.leading)"))
        // 손짓은 카드 모양 위에, 끌림 오프셋 **안쪽**에 붙는다 — 카드가 움직이면 손 받는 자리도 같이 움직인다.
        let shape = try Self.offset(of: ".contentShape(RoundedRectangle(cornerRadius:MegaphoneBannerPhoneRules.cornerRadius", in: code)
        let gesture = try Self.offset(of: ".simultaneousGesture(pressAndSwipe)", in: code)
        let drag = try Self.offset(of: ".offset(y:dragOffset)", in: code)
        #expect(shape < gesture && gesture < drag)
    }

    @Test("위로 쓸면 닫기 · 누르고 있으면 멈춤: 판정과 그것을 부르는 손짓")
    func swipeToDismiss() throws {
        #expect(MegaphoneBannerPhoneRules.swipeDismisses(translation: -40, predictedEnd: -40))
        // 기준선: 짧고 느리게 끈 것은 닫지 않는다 — 거리 판정이 결과를 가른다.
        #expect(!MegaphoneBannerPhoneRules.swipeDismisses(translation: -20, predictedEnd: -60))
        // 짧아도 위로 튕기면 닫는다(예측 끝점).
        #expect(MegaphoneBannerPhoneRules.swipeDismisses(translation: -10, predictedEnd: -120))
        // 아래로는 아무리 세게 끌어도 안 닫힌다.
        #expect(!MegaphoneBannerPhoneRules.swipeDismisses(translation: 60, predictedEnd: 300))
        #expect(MegaphoneBannerPhoneRules.dragOffset(translation: -50) == -50)
        #expect(MegaphoneBannerPhoneRules.dragOffset(translation: 40) == 10)
        #expect(MegaphoneBannerPhoneRules.dragOffset(translation: 400) == MegaphoneBannerPhoneRules.downwardLimit)
        // 나가는 거리는 카드 높이를 따라 화면 위 밖까지.
        #expect(MegaphoneBannerPhoneRules.slideOutOffset(cardHeight: 150) == -270)
        #expect(MegaphoneBannerPhoneRules.slideOutOffset(cardHeight: 0) == -MegaphoneBannerPhoneRules.topClearance)

        let code = Self.squashed(try IntegrationContractTests.code(Self.overlayPath))
        #expect(code.contains("DragGesture(minimumDistance:0,coordinateSpace:.global)"))
        #expect(code.contains("if!isPressing{isPressing=truestore.pauseTimer()}"), "누르는 순간 타이머를 안 멈춘다")
        #expect(code.contains(
            "ifMegaphoneBannerPhoneRules.swipeDismisses(translation:value.translation.height,predictedEnd:value.predictedEndTranslation.height){store.dismissCurrent()}else{"
        ), "놓을 때 쓸기 판정이 닫기를 부르지 않는다")
        #expect(code.contains("dragOffset=0}store.resumeTimer()"), "제자리로 돌아간 뒤 다시 세지 않는다")
        #expect(code.contains("onClose:{store.dismissCurrent()}"))
        // 동작 줄이기면 페이드만 · 아니면 이동만(불투명도를 이징하지 않는다).
        #expect(code.contains("ifreduceMotion{return.opacity}"))
        #expect(code.contains("insertion:.offset(y:hidden)") && code.contains("removal:.offset(y:hidden)"))
    }

    // MARK: 미룸

    @Test("미룸 집계: 시트 · 대결 화면 · 미니게임 판 중 하나면 미룬다 · 알릴 때만 알린다")
    func deferralRules() {
        #expect(!MegaphoneBannerPhoneRules.isDeferred(modalPresented: false, matchScreenVisible: false, miniGameRoundPlaying: false))
        #expect(MegaphoneBannerPhoneRules.isDeferred(modalPresented: true, matchScreenVisible: false, miniGameRoundPlaying: false))
        #expect(MegaphoneBannerPhoneRules.isDeferred(modalPresented: false, matchScreenVisible: true, miniGameRoundPlaying: false))
        #expect(MegaphoneBannerPhoneRules.isDeferred(modalPresented: false, matchScreenVisible: false, miniGameRoundPlaying: true))
        #expect(MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred: true, hasCurrent: true, hasQueue: false))
        #expect(!MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred: true, hasCurrent: false, hasQueue: true))
        #expect(MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred: false, hasCurrent: false, hasQueue: true))
        #expect(!MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred: false, hasCurrent: true, hasQueue: true))
        #expect(!MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred: false, hasCurrent: false, hasQueue: false))
        #expect(MegaphoneBannerPhoneRules.deferralPollKey(currentID: nil, queueCount: 0) == nil)
        #expect(MegaphoneBannerPhoneRules.deferralPollKey(currentID: "m", queueCount: 0) != nil)
        #expect(MegaphoneBannerPhoneRules.deferralPollKey(currentID: nil, queueCount: 2) != nil)
    }

    @Test("미룸 배선: 시트가 뜨면 떠 있던 배너를 줄로 되돌리고 새 배너도 기다린다 · 닫히면 띄운다 · 기준선: 시트 없으면 그대로")
    func deferralWiring() async throws {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
        }
        defer { h.tearDown() }
        await MegaphoneBannerPhoneTests.settleBanner(h)
        let modal = MegaphoneModalSwitch()
        h.model.megaphoneModalProbe = { modal.on }
        let store = h.model.megaphoneBanner
        #expect(!h.model.isMegaphoneBannerDeferred)

        store.presentFromPush(megaphoneID: "mgA", senderName: "확성기님", body: "📢 하나", senderID: MegaphoneBannerPhoneTests.peerMega)
        #expect(store.current?.megaphoneID == "mgA")
        h.model.syncMegaphoneBannerDeferral()
        #expect(store.current?.megaphoneID == "mgA", "미룰 것이 없는데 배너를 거뒀다")

        modal.on = true
        #expect(h.model.isMegaphoneBannerDeferred)
        h.model.syncMegaphoneBannerDeferral()
        #expect(store.current == nil, "시트 밑에 깔린 배너가 그대로 8초를 흘린다")
        #expect(store.queue.map(\.megaphoneID) == ["mgA"])
        // 스토어가 띄우기 전에 앱 모델의 미룸을 묻는다(init 배선).
        store.presentFromPush(megaphoneID: "mgB", senderName: "확성기님", body: "📢 둘", senderID: MegaphoneBannerPhoneTests.peerMega)
        #expect(store.current == nil, "시트가 떠 있는데 새 배너가 떴다")

        modal.on = false
        h.model.syncMegaphoneBannerDeferral()
        #expect(store.current != nil, "시트가 닫혔는데 기다리던 배너가 안 뜬다")
        await h.settle()

        let overlay = Self.squashed(try IntegrationContractTests.code(Self.overlayPath))
        #expect(overlay.contains(".onChange(of:model.games.isAnyMatchScreenVisible){_,_inmodel.syncMegaphoneBannerDeferral()}"))
        #expect(overlay.contains(".task(id:pollKey)") && overlay.contains("model.syncMegaphoneBannerDeferral()}}}"))
        let model = Self.squashed(try IntegrationContractTests.code(Self.modelPath))
        #expect(model.contains("matchScreenVisible:games.isAnyMatchScreenVisible"))
        #expect(model.contains("miniGameRoundPlaying:games.miniGames.controller?.isPlaying??false"))
        let app = Self.squashed(try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileAppModel.swift"))
        #expect(app.contains("megaphoneBanner.isBannerDeferred={[weakself]inself?.isMegaphoneBannerDeferred??false}"))
    }

    // MARK: [답장]

    @Test("[답장]: 보낸 사람 1:1 대화를 열고 이름을 넘기고 닫는다 · 기준선: 내 배너는 닫기만")
    func replyRoute() async throws {
        let h = await MessagesHarness.make { server in
            server.override("megaphone_inbox") { _ in .json("[]") }
        }
        defer { h.tearDown() }
        await MegaphoneBannerPhoneTests.settleBanner(h)
        let store = h.model.megaphoneBanner
        let router = h.model.router

        let own = MegaphoneBanner(messageID: nil, megaphoneID: "mgOwn", senderID: "me", senderName: "나", senderAvatarURL: nil,
                                  body: "내 글", createdAt: Date(), isOwn: true)
        #expect(MegaphoneBannerPhoneRules.replyRoute(for: own) == nil)
        let before = router.lastOpenedRoute
        h.model.replyToMegaphoneBanner(own)
        #expect(router.lastOpenedRoute == before, "내 배너 [답장]이 대화를 열었다")

        let peer = "P-Reply"
        #expect(h.model.messages.peerName(for: "p-reply") == nil, "기준선: 이력에 이 사람이 이미 있다")
        store.presentFromPush(megaphoneID: "mgR", senderName: "확성기님", body: "📢 답장해 줘", senderID: peer)
        let banner = try #require(store.current)
        #expect(MegaphoneBannerPhoneRules.replyRoute(for: banner) == .message(peerID: "p-reply"))
        h.model.replyToMegaphoneBanner(banner)
        #expect(router.lastOpenedRoute == .message(peerID: "p-reply"))
        #expect(router.selectedTab == .messages)
        #expect(store.current == nil, "[답장] 뒤 배너가 남았다")
        #expect(h.model.messages.peerName(for: "p-reply") == "확성기님", "빈 대화 머리에 이름이 안 넘어갔다")
        h.model.messages.reset()
        #expect(h.model.messages.peerName(for: "p-reply") == nil, "로그아웃 뒤에도 이름이 남는다")
        await h.settle()

        let overlay = Self.squashed(try IntegrationContractTests.code(Self.overlayPath))
        #expect(overlay.contains("onReply:{model.replyToMegaphoneBanner(banner)}"))
        #expect(overlay.contains("ifbanner.canReply{AingButton(MegaphoneBannerPhoneText.reply"))
        let model = Self.squashed(try IntegrationContractTests.code(Self.modelPath))
        #expect(model.contains("context.router.open(route)}megaphoneBanner.dismissCurrent()"))
    }
}
