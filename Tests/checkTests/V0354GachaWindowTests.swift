import AppKit
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import check
@testable import CheckCore

// v0.3.54 — 맥 캐릭터 뽑기 창(캡슐 기계). 상점 뽑기 패널의 [뽑기 · 50] · 캐릭터 고르기의 잠긴 황금 아잉이가 이 창을 연다.
//
// 재는 것:
//  · 창 수명 — 한 번 만들고 다시 쓴다 · 닫아도 파괴 안 함 · 닫혔다 다시 열면 새 기계(왕복 중 · 결과를 못 본 판이면 그대로) ·
//    안 보이면 기계 멈춤(커밋 전 자동 회전 · [한 번 더] 도 거둔다 — 닫은 창에서 루비가 안 나간다).
//  · 사용자 화면 — 테스트가 띄운 창은 모든 화면 밖 · 클릭 통과 · 키를 안 가져간다(사용자 지시 2026-10-16).
//  · 문 — 패널 버튼은 뽑지 않고 창을 연다 · 잠긴 이유 · 뽑기 없는 서버면 창도 없다 · 로그아웃이면 창이 내려간다.
//  · 돈 길 — 기계의 `pull` 이 스토어 뽑기 하나로 간다: 한 판에 RPC 한 번 · 결과 모름 실패 뒤 같은 요청 id · 실패면 공개 없음.
// 스텁 서버는 `GomokuStubProtocol`(호스트별 응답) — 실서버에 안 나간다. 창 시험은 `--no-parallel` 로 돌린다.

// MARK: - 도우미

@MainActor
private final class GWClock {
    var now = Date(timeIntervalSinceReferenceDate: 810_000_000)
    func advance(_ s: Double) { now = now.addingTimeInterval(s) }
}

@MainActor
private final class GWHookCounter {
    var shows = 0
    var closes = 0
    var hooks: GachaWindowHooks {
        GachaWindowHooks(show: { [self] in shows += 1 }, close: { [self] in closes += 1 })
    }
}

@MainActor
private func gwController(_ store: WorkTimerStore) -> CheckGachaWindowController {
    let controller = CheckGachaWindowController()
    controller.configure(store: store, content: { _, _, _ in AnyView(Color.clear) })
    return controller
}

private func gwHost(_ label: String) -> String { "v0354-gwin-\(label)-\(UUID().uuidString.prefix(8))".lowercased() }

/// 창 콘텐츠가 기계에 넘기는 값 그대로(`CheckGachaWindowView.machine`) — 감독을 뷰 없이 몬다.
@MainActor
private func gwEnv(_ store: WorkTimerStore) -> GachaMachineEnv {
    GachaMachineEnv(balance: store.rubyBalance ?? 0, cost: store.gachaInfo?.price ?? 0, shards: store.gachaShards ?? 0,
                    ruby: Image(systemName: "circle"), portrait: { _ in Image(systemName: "circle") }, art: .vector,
                    teaseChance: 0, haptics: GachaMachineNoHaptics(), pull: CheckGachaWindowView.pullAction(store),
                    onAgain: {}, onClose: {}, blockedReason: store.gachaWindowBlockedReason,
                    againEnabled: store.gachaExchangingID == nil && store.purchasingID == nil,
                    isActive: true, reduceMotion: false, onFrame: nil)
}

/// 손잡이 클릭(자동 회전) → 한 바퀴 끝 → 커밋.
@MainActor
private func gwTurn(_ d: GachaMachineDirector, _ clock: GWClock) {
    d.autoTurn(clock.now)
    clock.advance(d.autoTurnDuration)
    d.advance(clock.now)
}

/// 결과가 도착한 판을 공개가 자리 잡을 때까지(톡톡 건너뛰기 → 버튼이 뜰 때).
@MainActor
private func gwSettle(_ d: GachaMachineDirector, _ clock: GWClock) {
    if let ds = d.dropStart { clock.now = max(clock.now, ds.addingTimeInterval(d.drop.total + 0.01)) }
    d.advance(clock.now)
    d.skipTaps(clock.now)
    if let r = d.result { clock.advance(d.goldBuild + d.buttonsAt(r.kind) + 0.05) }
    d.advance(clock.now)
}

// MARK: - 창 수명 · 사용자 화면

@MainActor
@Suite(.serialized)
struct V0354GachaWindowLifecycleTests {
    @Test("창 계약: 제목 · 고유 자동저장 이름 = 식별자 · 고정 420×552 · 크기 고정 · 닫아도 해제 안 함 · 외관은 시스템을 따른다")
    func windowIdentityMatchesTheContract() {
        #expect(CheckGachaWindowController.windowTitle == "캐릭터 뽑기")
        #expect(CheckGachaWindowController.frameAutosaveName == "check.gacha.window")
        let others = [CheckChessWindowController.frameAutosaveName, CheckGomokuWindowController.frameAutosaveName,
                      CheckMiniGameWindowController.frameAutosaveName, CheckSettingsWindowController.frameAutosaveName]
        #expect(!others.contains(CheckGachaWindowController.frameAutosaveName), "자동저장 이름이 다른 창과 겹치면 자리 저장이 죽는다")
        #expect(CheckGachaWindowController.fixedContentSize == NSSize(width: 420, height: 552))
        // 기계(380×460)는 폭에 맞춰 ×1.105 → 아래 띠 ≈ 22pt 에 "확률 보기" 가 선다(기계 안내 알약과 안 겹친다).
        #expect(abs(GachaWindowLayout.stageScale - 420.0 / 380.0) < 0.0001)
        #expect(GachaWindowLayout.bandHeight > 20 && GachaWindowLayout.bandHeight < 24)

        let window = CheckGachaWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "캐릭터 뽑기")
        #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable) && window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.isReleasedWhenClosed, "닫힘에 해제가 딸리면 다음 show() 가 해제된 창을 만진다")
        #expect(!window.hidesOnDeactivate)
        #expect(window.appearance == nil, "외관을 못 박았다 — 기계의 밝은·어두운 테마 중 하나가 죽는다(시스템을 따른다)")
        #expect(window.identifier?.rawValue == CheckGachaWindowController.frameAutosaveName)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
        #expect(window.ignoresMouseEvents, "테스트가 만든 창이 클릭을 받는다 — 사용자 화면의 그 자리가 막힌다")
    }

    @Test("한 번 만들고 다시 쓴다(멱등) · 닫아도 창은 남는다 · 테스트 창은 모든 화면 밖 · 클릭 통과 · 키를 안 가져간다")
    func lazyIdempotentOffscreenAndSurvivesClose() throws {
        let store = V0354GachaMacRenderTests.store()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }

        #expect(!controller.hasWindow, "배선만으로 창이 만들어졌다")
        controller.show()
        #expect(controller.hasWindow && controller.isOpen)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹쳐 자리 저장이 죽었다")
        let first = try #require(controller.currentWindow)
        // ★ 사용자 화면에 아무것도 없다: 어느 화면과도 안 겹친다 · 클릭 통과 · 키 아님 · 알파 0.
        #expect(!NSScreen.screens.isEmpty, "전제: 화면이 있다(화면 밖 판정이 아무것도 안 재지 않게)")
        print("[v0354-gacha-window] 테스트 창 \(first.frame) · 화면 \(NSScreen.screens.map(\.frame))")
        for screen in NSScreen.screens {
            #expect(!screen.frame.intersects(first.frame), "테스트 창 \(first.frame) 이 화면 \(screen.frame) 에 걸쳤다")
        }
        #expect(first.ignoresMouseEvents && !first.isKeyWindow && first.alphaValue == 0)
        #expect(first.isVisible, "전제: 창은 실제로 올라갔다(화면 밖에) — 아니면 아래 '보임' 시험이 아무것도 못 잰다")

        controller.show()
        controller.show()
        #expect(controller.currentWindow === first, "show() 를 더 불렀더니 창이 바뀌었다(멱등 위반)")
        controller.close()
        #expect(!controller.isOpen && !controller.state.isActive)
        #expect(controller.hasWindow, "닫기가 창을 파괴했다 — 옮겨 둔 자리가 매번 초기화된다")
        #expect(!first.isVisible)
        controller.show()
        #expect(controller.isOpen && controller.currentWindow === first)
    }

    @Test("배선 전에는 show() 가 아무것도 안 만든다")
    func withoutWiringShowDoesNothing() {
        let controller = CheckGachaWindowController()
        controller.show()
        #expect(!controller.hasWindow && !controller.isOpen)
    }

    @Test("안 보이면 기계를 멈춘다: 최소화 · 완전히 가려짐 · 빨간 점 닫기 → isActive 거짓, 되살리면 참(AppKit 알림 그대로)")
    func machinePausesWhenTheWindowIsNotVisible() throws {
        let store = V0354GachaMacRenderTests.store()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        #expect(!controller.state.isActive, "기준선: 열기 전에는 멈춰 있다")
        controller.show()
        let window = try #require(controller.currentWindow)
        #expect(controller.state.isActive, "창을 열었는데 기계가 멈춰 있다")

        // AppKit 이 던지는 그 알림을 그대로 던진다(메서드 직접 호출은 배선이 빠져도 초록이다).
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        #expect(!controller.state.isActive, "최소화했는데 기계가 돈다")
        NotificationCenter.default.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        #expect(controller.state.isActive, "되살렸는데 기계가 멈춰 있다")

        // 가림도 AppKit 알림 그대로 — 화면 밖 테스트 창의 가림 상태는 '안 보임'이라 위임 메서드가 그 값을 읽어 옮긴다.
        #expect(!window.occlusionState.contains(.visible),
                "전제: 화면 밖 테스트 창의 가림 상태는 '안 보임'이다 — 아니면 아래 알림이 아무것도 안 잰다")
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        #expect(!controller.state.isActive, "완전히 가려졌는데 기계가 돈다 — windowDidChangeOcclusionState 배선이 빠졌다")
        // '보임' 쪽은 화면 밖 창으로 만들 수 없어 판정 값을 넣는다.
        controller.applyOcclusion(visible: true)
        #expect(controller.state.isActive)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(!controller.isOpen && !controller.state.isActive, "빨간 점으로 닫았는데 기계가 돈다")
        // 닫힌 창의 가림 통지는 '보임'으로 되살리지 못한다.
        controller.applyOcclusion(visible: true)
        #expect(!controller.state.isActive)
        controller.show()
        #expect(controller.state.isActive)
    }

    @Test("닫혔다 다시 열면 새 기계(지난 공개 화면이 안 남는다) · 뽑기 왕복 중이면 그대로 · 열린 창을 다시 불러도 그대로")
    func reopeningAClosedWindowStartsAFreshMachine() throws {
        let store = V0354GachaMacRenderTests.store()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let firstID = controller.state.contentID
        controller.show()
        #expect(controller.state.contentID == firstID, "열린 창을 앞으로 부르기만 했는데 기계가 새로 섰다(보던 판이 사라진다)")

        controller.state.showsOdds = true
        controller.close()
        #expect(!controller.state.showsOdds, "닫았는데 확률 판이 남았다")
        controller.show()
        #expect(controller.state.contentID == firstID + 1, "닫혔던 창을 다시 열었는데 지난 기계가 그대로다 — [닫기] 가 방금 연 창을 또 닫는다")

        // 뽑기 왕복이 떠 있는 채 닫았다 다시 열면 — 그 판을 이어서 보여 준다(새 기계가 같은 순간 손잡이를 받지 않게).
        controller.close()
        store.gachaPulling = true
        controller.show()
        #expect(controller.state.contentID == firstID + 1, "왕복 중인데 기계를 새로 세웠다 — 그 판의 공개가 사라진다")
        store.gachaPulling = false
    }

    @Test("뽑은 판이 공개되기 전에 창을 닫았다 다시 열면 그 기계를 그대로 둔다(산 캡슐을 끝까지 본다) — 공개가 자리 잡았으면 새 기계")
    func reopeningKeepsAnUnrevealedPaidTurn() async throws {
        let host = gwHost("reopen")
        V0354GachaStub.register(host: host, pull: { _ in .init(body: V0354GachaWindowPullTests.okFox, delay: 0.2) })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-reopen")
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        let clock = GWClock()
        let d = GachaMachineDirector(clock: { [clock] in clock.now })
        d.autoSchedule = false
        d.update(env: gwEnv(store))
        controller.state.machineLink.attach(d)            // 실제 창 콘텐츠는 기계가 그릴 때 스스로 물린다(아래 실제 창 시험)
        controller.show()
        let id0 = controller.state.contentID
        gwTurn(d, clock)                                  // 손잡이 한 바퀴 → 스토어 뽑기(RPC)
        #expect(await V0354CoreStub.waitUntil { store.gachaPulling }, "전제: 기계의 pull 이 스토어 뽑기로 갔다")
        controller.close()                                // 흔들리는 중에 닫았다
        await d.pullTask?.value                           // 닫힌 동안 RPC 가 돌아왔다(루비는 나갔다)
        #expect(!store.gachaPulling && d.result?.characterID == "fox" && !d.revealSettled(clock.now),
                "전제: 왕복은 끝났고 공개는 아직이다")
        controller.show()                                 // 상점 [뽑기 · 50] 으로 다시 연다
        #expect(controller.state.contentID == id0,
                "공개 전인 판이 있는데 기계를 새로 세웠다 — 루비 50 을 낸 캡슐을 창에서 못 본다")
        // 기준선(달라야 한다): 공개가 자리 잡은 뒤 닫았다 열면 새 기계.
        gwSettle(d, clock)
        #expect(d.revealSettled(clock.now))
        controller.close()
        controller.show()
        #expect(controller.state.contentID == id0 + 1, "공개가 끝난 판인데 지난 기계가 그대로다 — [닫기] 가 방금 연 창을 또 닫는다")
    }

    @Test("실제 창 · 실제 기계(화면 밖): 손잡이가 저절로 도는 중에 창을 닫으면 서버에 뽑기를 안 묻는다 — 열어 둔 기준선은 묻는다")
    func closingDuringTheAutoTurnSpendsNothing() async throws {
        for closeIt in [false, true] {
            let host = gwHost("e2e-\(closeIt)")
            V0354GachaStub.register(host: host, pull: { _ in .init(body: V0354GachaWindowPullTests.okFox) })
            let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-e2e-\(closeIt)")
            let controller = CheckGachaWindowController()
            controller.configure(store: store)            // 앱과 같은 콘텐츠(기계 + 확률 보기)
            defer { controller.discardWindowForTesting() }
            controller.show()
            let window = try #require(controller.currentWindow)
            for screen in NSScreen.screens {
                #expect(!screen.frame.intersects(window.frame), "테스트 창 \(window.frame) 이 화면 \(screen.frame) 에 걸쳤다")
            }
            #expect(await V0354CoreStub.waitUntil { controller.state.machineLink.director?.env?.canPull == true },
                    "창 안 기계가 안 섰거나 뽑을 수 없다")
            let d = try #require(controller.state.machineLink.director)
            d.autoTurn()                                   // 손잡이 클릭(보이스오버 동작과 같은 문)
            #expect(d.autoTurnStart != nil, "전제: 손잡이가 저절로 돌기 시작했다")
            try await Task.sleep(for: .milliseconds(150))
            if closeIt { controller.close() }              // 도는 중에 ⌘W
            try await Task.sleep(for: .milliseconds(1_500))
            let pulls = GomokuStubProtocol.count(host: host, rpc: "gacha_pull")
            if closeIt {
                #expect(pulls == 0 && d.pullCount == 0, "닫은 창의 기계가 마저 돌아 뽑았다(RPC \(pulls)) — 창 없이 루비 50 이 나간다")
                #expect(d.env?.isActive == false, "닫은 창의 기계가 '안 보임'을 못 받았다 — 닫힌 창의 뷰가 다시 안 그려졌다")
            } else {
                #expect(pulls == 1, "기준선: 열어 둔 창의 기계가 다 돌았는데 서버에 안 물었다 — 위 '안 물음'이 아무것도 안 잰다")
            }
            await d.pullTask?.value
        }
    }

    @Test("로그아웃은 뽑기 창을 내린다(다음 사람이 앞 사람의 잔량·조각이 박힌 기계를 안 본다)")
    func signOutClosesTheWindow() {
        let store = V0354GachaMacRenderTests.store()
        let counter = GWHookCounter()
        store.gachaWindowHooks = counter.hooks
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        #expect(counter.closes == 0)
        store.signOut(notifyServer: false)
        #expect(counter.closes >= 1, "로그아웃했는데 뽑기 창을 안 내렸다")
        #expect(store.gachaInfo == nil)
    }

    @Test("서버가 뽑기를 거두면(gacha 없는 상점 응답) 떠 있던 창도 내린다 — 값·조각을 모르는 기계가 0 을 말하며 서 있지 않게")
    func gachaDisappearingClosesTheWindow() {
        let store = V0354GachaMacRenderTests.store()
        let counter = GWHookCounter()
        store.gachaWindowHooks = counter.hooks
        // 기준선: 뽑기가 있는 응답은 창을 건드리지 않는다.
        store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: V0354GachaMacRenderTests.shopRows(),
                                               gacha: V0354GachaMacRenderTests.info()))
        #expect(store.isGachaAvailable && counter.closes == 0, "뽑기가 그대로인데 창을 내렸다")
        store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: []))
        #expect(!store.isGachaAvailable && counter.closes == 1, "뽑기가 사라졌는데 창이 남았다")
    }

    @Test("뽑기 창은 독립 창 목록에 있다 — 미니게임 창을 띄워 둔 채 이 창에서 누른 스페이스를 게임이 삼키지 않는다")
    func spaceInTheGachaWindowIsNotTakenByTheMiniGame() {
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckGachaWindowController.frameAutosaveName))
        let game = gwBareWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
        let gacha = gwBareWindow(identifier: CheckGachaWindowController.frameAutosaveName)
        let unknown = gwBareWindow(identifier: nil)
        defer { [game, gacha, unknown].forEach { $0.orderOut(nil) } }
        #expect(MiniGameSpaceKey.yieldsToOtherWindow(gacha, gameWindow: game), "뽑기 창으로 간 스페이스를 미니게임이 삼킨다")
        #expect(!MiniGameSpaceKey.yieldsToOtherWindow(unknown, gameWindow: game), "전제: 모르는 창에는 양보하지 않는다(기준선)")
    }
}

/// 모든 화면 밖 · 알파 0 · 클릭 통과의 맨 창(식별자만 단다).
@MainActor
private func gwBareWindow(identifier: String?) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -30_000, y: 200, width: 120, height: 60),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.orderFront(nil)
    return window
}

// MARK: - 문 · 잠금

@MainActor
@Suite struct V0354GachaWindowDoorTests {
    @Test("[뽑기 · 50] 은 창을 연다(상점을 다시 읽고) — 여기서는 뽑지 않는다 · 뽑기가 없는 서버면 창도 없다")
    func openingTheWindowDoesNotPull() async throws {
        let host = gwHost("open")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-open")
        let counter = GWHookCounter()
        store.gachaWindowHooks = counter.hooks
        let reads = GomokuStubProtocol.count(host: host, rpc: "shop_state")
        store.openGachaWindow()
        #expect(counter.shows == 1, "창을 안 열었다")
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") == reads + 1 },
                "창을 열며 상점을 다시 안 읽었다 — 다른 기기에서 바뀐 잔량·조각이 낡은 채 선다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 0, "창을 여는 것만으로 뽑았다")

        // 기준선: 서버가 뽑기를 안 준다(옛 서버) — 창을 안 연다.
        let bare = V0354GachaMacRenderTests.store()
        let bareCounter = GWHookCounter()
        bare.gachaWindowHooks = bareCounter.hooks
        bare.gachaInfo = nil
        bare.openGachaWindow()
        #expect(bareCounter.shows == 0, "뽑기가 없는 서버인데 창을 열었다 — 공개하지 못한 확률로 루비를 받는다")
        #expect(bare.gachaNotice == GachaText.unavailable)
    }

    @Test("캐릭터 고르기의 잠긴 황금 아잉이 → 뽑기 창(상점은 안 연다) · 다른 잠긴 카드 → 상점 · 뽑기 없는 서버의 금 → 상점 + 얻는 길")
    func lockedGoldOpensTheWindow() async throws {
        let host = gwHost("locked")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-locked")
        let counter = GWHookCounter()
        store.gachaWindowHooks = counter.hooks
        store.openShopForLockedCharacter(CharacterCatalog.goldAingID)
        #expect(counter.shows == 1 && !store.isShopPanelVisible, "잠긴 금 카드가 창 대신 상점을 열었다")

        store.openShopForLockedCharacter("fox")
        #expect(counter.shows == 1 && store.isShopPanelVisible && !store.isGachaPanelOpen)
        store.closeShopPanel()

        store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: []))   // 옛 서버: gacha 없음
        #expect(!store.isGachaAvailable)
        store.openShopForLockedCharacter(CharacterCatalog.goldAingID)
        #expect(counter.shows == 1, "뽑기가 없는데 창을 열었다")
        #expect(store.isShopPanelVisible && store.shopNotice == GachaText.gachaOnlyHint)
    }

    @Test("[뽑기 · 50] 잠금과 이유: 모자람 · 잔량 모름 · 뽑기 없음 · 왕복 중이면 잠기고 이유를 말한다 — 뽑을 수 있으면 열린다")
    func pullButtonIsDisabledWithAReason() {
        let ready = V0354GachaMacRenderTests.store(ruby: 120)
        #expect(CheckGachaPanel.pullButtonState(ready).enabled && CheckGachaPanel.pullButtonState(ready).reason == nil)

        let short = V0354GachaMacRenderTests.store(ruby: 30)
        #expect(!CheckGachaPanel.pullButtonState(short).enabled)
        #expect(CheckGachaPanel.pullButtonState(short).reason == "루비 20개 더 필요해요")

        let unknown = V0354GachaMacRenderTests.store(ruby: nil)
        #expect(!CheckGachaPanel.pullButtonState(unknown).enabled)
        #expect(CheckGachaPanel.pullButtonState(unknown).reason == "루비 잔량을 아직 못 읽었어요")

        let none = V0354GachaMacRenderTests.store(ruby: 120)
        none.gachaInfo = nil
        #expect(!CheckGachaPanel.pullButtonState(none).enabled)
        #expect(CheckGachaPanel.pullButtonState(none).reason == GachaText.unavailable)

        let busy = V0354GachaMacRenderTests.store(ruby: 120)
        busy.gachaPulling = true
        #expect(!CheckGachaPanel.pullButtonState(busy).enabled, "왕복 중인데 버튼이 열려 있다")
    }

    @Test("패널의 [뽑기 · 50] 은 창을 여는 문이다 — 패널에서 곧장 뽑는 길·결과 연출이 남아 있지 않다(주석을 걷어낸 소스)")
    func panelButtonOpensTheWindowNotAPull() throws {
        let sources = try V0325TooltipTests.strippedSources()
        let panel = try #require(sources["CheckGachaPanel.swift"])
        #expect(panel.contains("store.openGachaWindow()"), "패널 버튼이 창을 안 연다")
        #expect(!panel.contains("store.pullGacha()"), "패널에서 곧장 뽑는 길이 남아 있다 — 연출 없는 뽑기가 생긴다")
        #expect(!panel.contains(".spring("), "패널에 옛 0.8초 결과 연출이 남아 있다")
        // 앱의 어떤 화면도 `pullGacha()` 를 부르지 않는다(실제 뽑기는 창 기계의 `pullGachaForReveal` 하나).
        let callers = sources.filter { $0.key != "WorkTimerStoreGacha.swift" && $0.value.contains(".pullGacha()") }.keys.sorted()
        #expect(callers.isEmpty, "화면이 연출 없는 뽑기 문을 부른다: \(callers)")
        let window = try #require(sources["CheckGachaWindow.swift"])
        #expect(window.contains("store.pullGachaForReveal()"))
        #expect(window.contains("isActive: state.isActive"), "창 기계에 '보이는가'가 안 들어간다 — 닫힌 창이 계속 그린다")
        let app = try #require(sources["CheckApp.swift"])
        #expect(app.contains("CheckGachaWindowController.shared.configure(store: store)"), "앱이 뽑기 창을 배선하지 않는다")
    }

    @Test("창 기계가 손잡이를 막는 이유: 로그아웃 · 뽑기 없음 · 잔량 모름은 막고, 모자람은 기계가 스스로 말한다(막지 않는다)")
    func blockedReasonMapping() {
        #expect(WorkTimerStore.gachaWindowBlockedReason(signedIn: false, availability: .ready(price: 50)) == GachaText.notSignedIn)
        #expect(WorkTimerStore.gachaWindowBlockedReason(signedIn: true, availability: .unavailable) == GachaText.unavailable)
        #expect(WorkTimerStore.gachaWindowBlockedReason(signedIn: true, availability: .unknownBalance(price: 50))
                == "루비 잔량을 아직 못 읽었어요")
        #expect(WorkTimerStore.gachaWindowBlockedReason(signedIn: true, availability: .short(price: 50, missing: 20)) == nil)
        #expect(WorkTimerStore.gachaWindowBlockedReason(signedIn: true, availability: .ready(price: 50)) == nil)
    }
}

// MARK: - 돈 길: 기계 → 스토어 → RPC

@MainActor
@Suite struct V0354GachaWindowPullTests {
    nonisolated static let okFox = #"{"status":"ok","character_id":"fox","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":71,"price":50}"#
    nonisolated static let okSquirrelDup = #"{"status":"ok","character_id":"squirrel","duplicate":true,"shards_gained":1,"shards":4,"ruby_balance":71}"#
    nonisolated static let okGold = #"{"status":"ok","character_id":"aing_gold","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":71}"#

    @Test("결과 → 연출 값: 이름은 맥 카탈로그 · 조각 수는 서버 값(중복이면 칩이 3 → 4) · 황금은 황금 갈래 · 잔량은 서버 값")
    func revealCarriesTheServerValues() async throws {
        let host = gwHost("reveal")
        V0354GachaStub.register(host: host, pull: { index in
            switch index {
            case 0: return .init(body: Self.okFox)
            case 1: return .init(body: Self.okSquirrelDup)
            default: return .init(body: Self.okGold)
            }
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-reveal")
        let fox = try await store.pullGachaForReveal()
        #expect(fox == GachaRevealOutcome(characterID: "fox", name: "여우", kind: .new, shardCount: 3, shardsGained: 0))
        #expect(store.rubyBalance == 71, "잔량 \(String(describing: store.rubyBalance)) — 서버 값(71)이 아니다(클라 계산 70)")
        let dup = try await store.pullGachaForReveal()
        #expect(dup.kind == .duplicate && dup.name == "다람쥐" && dup.shardCount == 4 && dup.shardCountBefore == 3)
        let gold = try await store.pullGachaForReveal()
        #expect(gold.kind == .gold && gold.characterID == CharacterCatalog.goldAingID)
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 3)
    }

    @Test("실패면 공개가 없다: 모자람(서버 잔량으로 고침) · 업데이트 필요 · 결과 모름(같은 요청 id 를 쥔다) → 던진다, 다음 판은 같은 id")
    func failuresThrowWithoutReveal() async throws {
        let host = gwHost("fail")
        V0354GachaStub.register(host: host, pull: { index in
            switch index {
            case 0: return .init(body: #"{"status":"needs_update"}"#)
            case 1: return .init(status: 503, body: #"{"message":"upstream"}"#)
            case 2: return .init(body: #"{"status":"ok","character_id":"fox","duplicate":false,"shards":3,"ruby_balance":70,"replayed":true}"#)
            default: return .init(body: #"{"status":"insufficient","need":50,"have":30}"#)
            }
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-fail")
        await #expect(throws: GachaRevealFailure(message: GachaText.needsUpdate)) { try await store.pullGachaForReveal() }
        await #expect(throws: GachaRevealFailure(message: GachaText.connection)) { try await store.pullGachaForReveal() }
        #expect(store.rubyBalance == 120, "결과를 모르는데 잔량이 움직였다")
        let replayed = try await store.pullGachaForReveal()
        #expect(replayed.characterID == "fox")
        await #expect(throws: GachaRevealFailure(message: GachaText.shortfall(need: 50, have: 30))) { try await store.pullGachaForReveal() }
        #expect(store.rubyBalance == 30, "서버가 말한 잔량(30)으로 안 고쳤다")
        let ids = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").compactMap(V0354GachaStub.requestID)
        #expect(ids.count == 4)
        #expect(ids[1] == ids[2], "결과를 모르는 실패 뒤 다음 판이 새 id 로 물었다 — 서버가 두 번 깎을 수 있다")
        #expect(ids[0] != ids[1] && ids[2] != ids[3], "답을 받은 뒤에도 같은 id 를 썼다")
        // 이제 화면이 아는 잔량 30 < 50 — 서버에 안 묻고 이유를 던진다.
        await #expect(throws: GachaRevealFailure(message: "루비 20개 더 필요해요")) { try await store.pullGachaForReveal() }
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 4, "모자란데 서버에 물었다")
    }

    @Test("교환 왕복 중이면 스토어가 막는다 — 서버에 안 묻고 실패 한 줄(공개 없음)")
    func busyStoreRefusesWithoutAnRPC() async throws {
        let host = gwHost("busy")
        V0354GachaStub.register(host: host, pull: { _ in .init(body: Self.okFox) })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-busy")
        store.gachaExchangingID = "fox"
        // 앞 동작의 한 줄이 남아 있어도 그 말을 실패 줄로 빌려 쓰지 않는다(기준선: 남은 한 줄은 "교환했어요").
        store.gachaNotice = GachaText.exchanged(name: "다람쥐")
        await #expect(throws: GachaRevealFailure(message: GachaText.pullFailed)) { try await store.pullGachaForReveal() }
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 0)
        store.gachaExchangingID = nil
    }

    @Test("기계 한 판 = RPC 한 번: 도는 동안 다시 돌리기 · 커밋 · [한 번 더] 를 눌러도 하나 · 공개가 자리 잡은 뒤 [한 번 더] 는 새 id 로 하나 더")
    func oneRPCPerMachineTurn() async throws {
        let host = gwHost("turn")
        V0354GachaStub.register(host: host, pull: { index in
            .init(body: index == 0 ? Self.okFox : Self.okSquirrelDup, delay: 0.2)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-turn")
        let clock = GWClock()
        let d = GachaMachineDirector(clock: { [clock] in clock.now })
        d.autoSchedule = false
        d.update(env: gwEnv(store))

        gwTurn(d, clock)
        #expect(d.pullInFlight, "손잡이가 다 돌았는데 pull 을 안 불렀다")
        #expect(await V0354CoreStub.waitUntil { store.gachaPulling }, "기계의 pull 이 스토어 뽑기로 안 갔다")
        // 연타 · 다시 돌리기 · 커밋 직접 · [한 번 더]
        d.autoTurn(clock.now)
        d.commit(clock.now)
        d.again(clock.now)
        await d.pullTask?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 1, "한 판에 RPC \(GomokuStubProtocol.count(host: host, rpc: "gacha_pull")) 번")
        #expect(d.result?.characterID == "fox" && d.result?.kind == .new && d.failTime == nil)

        d.update(env: gwEnv(store))   // 뷰가 다시 그리며 넘기는 값(서버 잔량 71)
        gwSettle(d, clock)
        #expect(d.revealSettled(clock.now), "공개가 자리 잡지 않았다")
        d.again(clock.now)
        clock.advance(GTiming.againDelay)
        d.advance(clock.now)
        clock.advance(d.autoTurnDuration)
        d.advance(clock.now)
        await d.pullTask?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 2)
        #expect(d.result?.characterID == "squirrel" && d.result?.shardCount == 4)
        let ids = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").compactMap(V0354GachaStub.requestID)
        #expect(ids.count == 2 && ids[0] != ids[1], "[한 번 더] 가 앞 판의 요청 id 를 다시 썼다 — 재응답만 돌아온다")
    }

    @Test("기계 판의 결과 모름 실패: 공개 없이 한 줄(연결) · 다음 판은 같은 요청 id 로 묻는다")
    func machineFailureKeepsTheRequestID() async throws {
        let host = gwHost("mfail")
        V0354GachaStub.register(host: host, pull: { index in
            index == 0 ? .init(status: 503, body: "{}") : .init(body: Self.okFox)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "gwin-mfail")
        let clock = GWClock()
        let d = GachaMachineDirector(clock: { [clock] in clock.now })
        d.autoSchedule = false
        d.update(env: gwEnv(store))
        gwTurn(d, clock)
        await d.pullTask?.value
        #expect(d.result == nil && d.failText == GachaText.connection, "결과를 모르는 실패를 공개했거나 다른 말을 했다(\(d.failText))")
        clock.advance(GTiming.failHold + 0.01)
        d.advance(clock.now)
        #expect(d.phase(clock.now) == .idle)
        gwTurn(d, clock)
        await d.pullTask?.value
        #expect(d.result?.characterID == "fox")
        let ids = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").compactMap(V0354GachaStub.requestID)
        #expect(ids.count == 2 && ids[0] == ids[1], "결과를 모르는 실패 뒤 다음 판이 새 id 로 물었다")
    }
}

// MARK: - 실제 창 캡처(화면 밖 · 기본 실행에서는 꺼짐)

/// 실제 컨트롤러 · 실제 창 · 실제 콘텐츠(기계 + 확률 보기)를 **모든 화면 밖**에 세우고, 창 서버가 합성한 그림을 창 번호로 받는다.
/// 사용자 화면에는 아무것도 안 뜬다(화면 밖 · 클릭 통과 · 키 안 가져감). `CHECK_V0354_GACHA_WINDOW_SHOTS=<폴더>` 일 때만 돈다.
@MainActor
@Suite(.serialized)
struct V0354GachaWindowCaptureTests {
    nonisolated static let shotDir = ProcessInfo.processInfo.environment["CHECK_V0354_GACHA_WINDOW_SHOTS"]

    /// 창이 실제로 설 수 있는 모습만(잔량을 모르거나 뽑기가 없으면 창이 안 열리거나 내려간다 — 그 막힘 줄은 S1 정지 화면이 보인다).
    enum Scenario: String, CaseIterable { case idle, short, odds }

    static func store(_ scenario: Scenario) -> WorkTimerStore {
        let store = V0354GachaMacRenderTests.store(ruby: scenario == .short ? 30 : 420, shards: 3)
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        return store
    }

    @Test("실제 창(화면 밖): 밝은·어두운 외관 × 대기 · 모자람 · 확률 보기 — 그림이 비지 않고 창은 어느 화면에도 안 걸린다",
          .enabled(if: shotDir != nil))
    func captureTheRealWindow() async throws {
        let dir = try #require(Self.shotDir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (look, appearance) in [("light", NSAppearance(named: .aqua)), ("dark", NSAppearance(named: .darkAqua))] {
            for scenario in Scenario.allCases {
                let store = Self.store(scenario)
                let controller = CheckGachaWindowController()
                controller.configure(store: store)
                defer { controller.discardWindowForTesting() }
                controller.show()
                let window = try #require(controller.currentWindow)
                window.appearance = appearance
                for screen in NSScreen.screens {
                    #expect(!screen.frame.intersects(window.frame), "캡처 창이 화면 \(screen.frame) 에 걸쳤다")
                }
                #expect(window.ignoresMouseEvents && !window.isKeyWindow)
                if scenario == .odds { controller.state.showsOdds = true }
                // 화면 밖이라 그림을 받는 동안만 불투명하게(사용자에겐 여전히 안 보인다).
                window.alphaValue = 1
                try await Task.sleep(for: .milliseconds(900))
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                let id = CGWindowID(window.windowNumber)
                let image = try #require(CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]),
                                         "창 캡처 실패(\(look) \(scenario))")
                let distinct = Self.distinctColors(image)
                print("[v0354-gacha-window] \(look) \(scenario.rawValue): \(image.width)×\(image.height) · 색 \(distinct) · 창 \(window.frame)")
                #expect(image.width >= 420 && distinct > 200, "\(look) \(scenario): 창 그림이 비었다(색 \(distinct))")
                let url = URL(fileURLWithPath: dir).appendingPathComponent("mac-window-\(scenario.rawValue)-\(look).png")
                guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, image, nil)
                #expect(CGImageDestinationFinalize(dest))
                window.alphaValue = 0
            }
        }
    }

    static func distinctColors(_ image: CGImage) -> Int {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return 0 }
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4 * 7) {
            seen.insert(UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2]))
        }
        return seen.count
    }
}
