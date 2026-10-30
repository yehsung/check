import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 2026-10-30 — 확성기 배너 맥 창(계약 docs/plan/megaphone-banner-contract.md "맥 배너").
//
// 진짜 `WorkTimerStore` + 진짜 `MegaphoneBannerStore`(시계 · 타이머 주입) + 진짜 패널(시험 실행이라 알파 0 · 화면 밖)로 잰다.
// 컨트롤러의 바깥 문(팝오버 · 마우스 · 화면 목록)은 가짜로 갈아 끼운다 — **진짜 팝오버 단추를 누르지 않는다.**
// 시험마다 비교 기준선을 둔다: 같은 자리에서 값 하나만 바꾸면 결과가 갈린다는 것을 함께 보인다.

/// 배너 스토어의 시계 · 타이머(8초를 기다리지 않는다 — 걸린 타이머를 시험이 손으로 부른다).
@MainActor
private final class MbpTimers {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var scheduled: [(after: TimeInterval, fire: @MainActor @Sendable () -> Void)] = []
}

/// 컨트롤러의 바깥 문.
@MainActor
private final class MbpWorld {
    var popovers = 0
    var mouse = CGPoint(x: 100, y: 100)
    var screens: [MegaphoneBannerLayout.Screen] = [
        .init(frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)),
        .init(frame: CGRect(x: 1_440, y: 0, width: 400, height: 800), visibleFrame: CGRect(x: 1_440, y: 0, width: 400, height: 776))
    ]
    var hooks: MegaphoneBannerWindowController.Hooks {
        MegaphoneBannerWindowController.Hooks(
            presentPopover: { [unowned self] in self.popovers += 1 },
            mouseLocation: { [unowned self] in self.mouse },
            screens: { [unowned self] in self.screens },
            reduceMotion: { false },
            schedule: { _, fire in fire() }
        )
    }
}

@MainActor
private func mbpStore(_ label: String, timers: MbpTimers, function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(projectURL: URL(string: "http://mbp-\(label)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults("mbp-" + label, function: function))
    store.megaphoneBanner.clock = { timers.now }
    store.megaphoneBanner.schedule = { after, fire in timers.scheduled.append((after, fire)) }
    return store
}

@MainActor
private func mbpWait(_ timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return true
}

private func mbpSource(_ relative: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let raw = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    return V0351IfConfig.strippingComments(raw)
}

/// `marker` 로 시작하는 선언의 본문(첫 `{` 부터 짝 맞는 `}` 까지).
private func mbpBody(_ source: String, after marker: String) -> String? {
    guard let start = source.range(of: marker) else { return nil }
    guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var index = open
    while index < source.endIndex {
        let ch = source[index]
        if ch == "{" { depth += 1 }
        if ch == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

@MainActor
@Suite("확성기 배너 맥 창")
struct MegaphoneBannerPanelTests {

    // MARK: 패널 속성

    @Test("패널: 키 불가 · 전 스페이스 · 전체화면 보조 · 캐릭터 패널 한 칸 위 · 공유 제외 · 비활성에도 안 숨음 — 시험 실행이면 알파 0 · 클릭 통과")
    func panelProperties() throws {
        #expect(CheckPanelVisibility.isRunningTests, "전제: 시험 실행 판정이 참이다(거짓이면 창이 사용자 화면에 뜬다)")
        let panel = MegaphoneBannerPanel.make()
        defer { panel.orderOut(nil) }
        #expect(!panel.canBecomeKey && !panel.canBecomeMain, "배너가 키를 잡는다 — 대결 중 키보드를 훔친다")
        #expect(panel.styleMask.contains(.borderless) && panel.styleMask.contains(.nonactivatingPanel))
        for behavior: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] {
            #expect(panel.collectionBehavior.contains(behavior), "collectionBehavior 에 \(behavior.rawValue) 가 없다")
        }
        #expect(panel.sharingType == .none, "화면 공유에 배너가 비친다")
        #expect(!panel.hidesOnDeactivate, "다른 앱을 쓰는 동안 배너가 숨는다")
        // 기준선: 캐릭터 패널(.floating). 배너는 그보다 정확히 한 칸 위다.
        let character = CheckOverlayController.makePanel(size: NSSize(width: 140, height: 170))
        defer { character.orderOut(nil) }
        #expect(character.level == .floating, "전제: 캐릭터 패널은 .floating")
        #expect(panel.level.rawValue == character.level.rawValue + 1, "배너 레벨 \(panel.level.rawValue) ≠ 캐릭터 패널 + 1")
        // 시험 실행: 알파 0 · 창 서버엔 클릭 통과 · 앱이 의도한 값은 '클릭 받음'(단추가 있는 창이다).
        #expect(panel.alphaValue == 0 && CheckPanelVisibility.productionAlpha == 1, "시험 실행인데 배너 알파가 0 이 아니다")
        #expect(panel.windowServerIgnoresMouseEvents, "시험 패널이 진짜 클릭을 먹는다")
        #expect(!panel.ignoresMouseEvents, "앱이 의도한 값이 클릭 통과다 — [답장] [닫기] 가 안 눌린다")
    }

    // MARK: 자리

    @Test("자리: 폭 min(화면 폭 − 48, 520) · 마우스가 있는 화면의 위쪽 가운데 · 메뉴바 아래 12pt")
    func layoutMath() {
        // 폭 — 넓은 화면은 520 에 묶이고, 좁은 화면은 화면 폭 − 48(기준선: 둘이 다르다).
        #expect(MegaphoneBannerLayout.width(screenWidth: 1_440) == 520)
        #expect(MegaphoneBannerLayout.width(screenWidth: 400) == 352)
        let world = MbpWorld()
        // 마우스가 둘째 화면에 있으면 둘째 화면 · 첫째에 있으면 첫째(기준선).
        let second = MegaphoneBannerLayout.screen(containing: CGPoint(x: 1_600, y: 300), in: world.screens)
        let first = MegaphoneBannerLayout.screen(containing: CGPoint(x: 300, y: 300), in: world.screens)
        #expect(second == world.screens[1] && first == world.screens[0])
        let visible = world.screens[1].visibleFrame
        let card = MegaphoneBannerLayout.cardFrame(visibleFrame: visible, cardHeight: 90)
        #expect(card.maxY == visible.maxY - 12, "카드 위 끝이 메뉴바 아래 12pt 가 아니다(\(card.maxY))")
        #expect(abs(card.midX - visible.midX) <= 0.5, "카드가 가운데가 아니다")
        #expect(card.width == 352 && card.height == 90)
        let window = MegaphoneBannerLayout.windowFrame(visibleFrame: visible, cardHeight: 90)
        #expect(window.maxY == visible.maxY && window.minY == card.minY && window.height == 102,
                "창이 메뉴바 아래 끝까지 닿지 않는다(카드가 메뉴바 밑에서 미끄러져 나올 길)")
    }

    @Test("띄우기: current 가 서면 마우스 화면 자리로 계산해 화면 밖에 세운다 · 키를 안 잡는다 · current 가 비면 내린다")
    func controllerShowsAtMouseScreenAndParksOffscreen() async throws {
        let timers = MbpTimers()
        let store = mbpStore("show", timers: timers)
        let world = MbpWorld()
        world.mouse = CGPoint(x: 1_600, y: 400)            // 둘째(좁은) 화면
        let controller = MegaphoneBannerWindowController(store: store, hooks: world.hooks)
        controller.start()
        defer { controller.stop() }
        #expect(!controller.isOpen && controller.panel == nil, "전제: 배너가 없으면 창도 없다")
        store.megaphoneBanner.presentOwn(body: "📢 라운지에 간식 있어요", senderName: "나")
        #expect(await mbpWait { controller.isOpen }, "current 가 섰는데 창이 안 떴다(관찰 배선)")
        let panel = try #require(controller.panel)
        let card = try #require(controller.lastCardFrame)
        #expect(card.width == 352 && card.maxY == world.screens[1].visibleFrame.maxY - 12,
                "마우스가 있는 화면(둘째)에 자리 잡지 않았다: \(card)")
        #expect(panel.frame.origin == MegaphoneBannerLayout.testParkingOrigin, "시험 창이 화면 밖에 안 섰다: \(panel.frame)")
        #expect(panel.alphaValue == 0)
        #expect(!panel.isKeyWindow && NSApp.keyWindow !== panel, "배너가 키를 잡았다")
        #expect(controller.presentation.banner?.body == "라운지에 간식 있어요" && controller.presentation.isShown)
        // 기준선: 마우스를 첫째 화면으로 옮겨 다음 배너를 띄우면 폭이 520 이 된다(자리 계산이 마우스를 읽는다).
        store.megaphoneBanner.dismissCurrent()
        #expect(await mbpWait { !controller.isOpen }, "current 가 비었는데 창이 안 내려갔다")
        #expect(!panel.isVisible)
        #expect(timers.scheduled.last?.after == MegaphoneBannerRules.gap)
        timers.scheduled.last?.fire()                      // 쉬는 0.4초
        world.mouse = CGPoint(x: 300, y: 300)
        store.megaphoneBanner.presentOwn(body: "두 번째", senderName: "나")
        #expect(await mbpWait { controller.isOpen && controller.presentation.banner?.body == "두 번째" })
        #expect(controller.lastCardFrame?.width == 520)
    }

    // MARK: 호버

    @Test("호버: 들어오면 8초 타이머가 멈추고, 떠나면 남은 시간과 3초 중 긴 쪽으로 다시 센다(남은 2초 → 3초 · 남은 7초 → 7초)")
    func hoverPausesAndResumes() async throws {
        let timers = MbpTimers()
        let store = mbpStore("hover", timers: timers)
        let world = MbpWorld()
        let controller = MegaphoneBannerWindowController(store: store, hooks: world.hooks)
        controller.start()
        defer { controller.stop() }
        store.megaphoneBanner.presentOwn(body: "첫 배너", senderName: "나")
        #expect(await mbpWait { controller.isOpen })
        let hover = try #require(controller.hoverView, "호버 뷰가 없다")
        let options = try #require(hover.hoverTrackingArea?.options, "추적 영역이 없다")
        #expect(options.contains(.activeAlways) && options.contains(.mouseEnteredAndExited),
                "추적 영역이 키 아닌 패널에서 안 온다(.activeAlways 없음)")
        #expect(timers.scheduled.last?.after == MegaphoneBannerRules.displaySeconds, "전제: 8초 타이머")
        let firstTimer = try #require(timers.scheduled.last?.fire)

        timers.now += 6
        hover.onHoverChanged?(true)                       // 마우스가 들어왔다(추적 영역이 부르는 문)
        #expect(store.megaphoneBanner.isTimerPaused)
        firstTimer()                                       // 8초가 지났다 — 멈춰 있으니 안 닫힌다
        #expect(store.megaphoneBanner.current != nil, "호버 중인데 8초 타이머가 배너를 닫았다")
        timers.now += 100
        hover.onHoverChanged?(false)
        #expect(!store.megaphoneBanner.isTimerPaused)
        #expect(timers.scheduled.last?.after == 3, "남은 2초인데 3초로 다시 세지 않았다: \(String(describing: timers.scheduled.last?.after))")
        timers.scheduled.last?.fire()
        #expect(store.megaphoneBanner.current == nil, "다시 센 타이머가 배너를 안 닫았다")
        #expect(await mbpWait { !controller.isOpen })

        // 기준선: 1초 만에 올렸다 떠나면 남은 7초 그대로(3초 하한이 남은 시간을 줄이지 않는다).
        timers.scheduled.last?.fire()                      // 쉬는 0.4초
        store.megaphoneBanner.presentOwn(body: "둘째 배너", senderName: "나")
        #expect(await mbpWait { controller.isOpen && controller.presentation.banner?.body == "둘째 배너" })
        timers.now += 1
        hover.onHoverChanged?(true)
        timers.now += 50
        hover.onHoverChanged?(false)
        #expect(timers.scheduled.last?.after == 7, "남은 7초가 \(String(describing: timers.scheduled.last?.after))초로 바뀌었다")
    }

    // MARK: [답장]

    @Test("[답장]: 보낸 사람과의 대화(.overlay)를 이름과 함께 열고 팝오버를 한 번 띄운 뒤 배너를 닫는다 — 내 배너는 [답장] 이 없다")
    func replyOpensConversationWithName() async throws {
        let timers = MbpTimers()
        let store = mbpStore("reply", timers: timers)
        let world = MbpWorld()
        let controller = MegaphoneBannerWindowController(store: store, hooks: world.hooks)
        controller.start()
        defer { controller.stop() }
        store.megaphoneBanner.presentFromPush(megaphoneID: "mp-r", senderName: "확성기님", body: "📢 라운지에 간식 있어요",
                                              senderID: "peer-r")
        #expect(await mbpWait { controller.isOpen })
        #expect(controller.presentation.banner?.canReply == true)

        // 기준선: 힌트 없이 같은 사람의 대화를 열면 제목이 빈다(확성기 줄은 메시지함에서 빠지니 이름을 찾을 곳이 없다).
        let bare = mbpStore("reply-bare", timers: MbpTimers())
        bare.openMessagePanel(peer: "peer-r", from: .overlay)
        #expect(bare.selectedMessagePeerName == nil, "전제: 힌트 없이는 이름이 없다")

        controller.reply()
        #expect(world.popovers == 1, "팝오버를 \(world.popovers)번 띄웠다")
        #expect(store.isMessagePanelVisible && store.selectedMessagePeerID == "peer-r")
        #expect(store.messagePanelOrigin == .overlay, "[뒤로]가 홈이 아니다")
        #expect(store.selectedMessagePeerName == "확성기님", "대화 제목이 비었다")
        #expect(store.megaphoneBanner.current == nil, "[답장] 뒤에도 배너가 남았다")
        #expect(await mbpWait { !controller.isOpen })

        // 내 배너: [답장] 이 없다 — 눌러도(이론상) 팝오버도 대화도 없다.
        timers.scheduled.last?.fire()                      // 쉬는 0.4초
        store.megaphoneBanner.presentOwn(body: "내 확성기", senderName: "나")
        #expect(await mbpWait { controller.isOpen && controller.presentation.banner?.isOwn == true })
        #expect(controller.presentation.banner?.canReply == false)
        controller.reply()
        #expect(world.popovers == 1 && store.megaphoneBanner.current?.isOwn == true)
        // [닫기]
        controller.close()
        #expect(store.megaphoneBanner.current == nil)
        // 로그아웃이 이름 힌트를 비운다.
        store.resetMegaphoneBanner()
        #expect(store.messagePeerHint == nil)
    }

    // MARK: 미룸

    @Test("미룸: 오목 대결 중엔 안 뜨고 줄에 선다 → 대결이 끝나면 뜬다(컨트롤러 관찰) · 기준선: 대결이 없으면 바로 뜬다")
    func deferralHoldsBannerUntilMatchEnds() async throws {
        let timers = MbpTimers()
        let store = mbpStore("defer", timers: timers)
        let world = MbpWorld()
        let controller = MegaphoneBannerWindowController(store: store, hooks: world.hooks)
        controller.start()
        defer { controller.stop() }
        #expect(!store.megaphoneBanner.isBannerDeferred(), "전제: 대결이 없으면 미루지 않는다")
        store.gomoku.phase = .playing
        #expect(store.megaphoneBanner.isBannerDeferred(), "스토어가 배너 스토어에 미룸을 주입하지 않았다")
        #expect(await mbpWait { store.megaphoneBannerLastDeferred }, "컨트롤러가 대결 시작을 못 봤다")
        store.megaphoneBanner.presentFromPush(megaphoneID: "mp-d", senderName: "확성기님", body: "간식", senderID: "peer-d")
        #expect(store.megaphoneBanner.current == nil && store.megaphoneBanner.queue.count == 1, "대결 중인데 배너가 떴다")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(!controller.isOpen)
        store.gomoku.phase = .result
        #expect(await mbpWait { controller.isOpen && store.megaphoneBanner.current?.megaphoneID == "mp-d" },
                "대결이 끝났는데 기다리던 배너가 안 떴다")

        // 떠 있는 동안 테트리스 카운트다운이 시작되면 배너를 줄로 되돌린다.
        store.tetris.phase = .countdown
        #expect(await mbpWait { !controller.isOpen && store.megaphoneBanner.current == nil })
        #expect(store.megaphoneBanner.queue.first?.megaphoneID == "mp-d", "되돌린 배너가 줄 맨 앞에 없다")
        store.tetris.phase = .lobby
        #expect(await mbpWait { controller.isOpen })

        // 기준선: 미룸이 없는 스토어는 같은 푸시를 바로 띄운다.
        let plain = mbpStore("defer-plain", timers: MbpTimers())
        plain.megaphoneBanner.presentFromPush(megaphoneID: "mp-d", senderName: "확성기님", body: "간식", senderID: "peer-d")
        #expect(plain.megaphoneBanner.current?.megaphoneID == "mp-d")
    }

    @Test("미룸: 미니게임 판이 열리면(창이 열려 있을 때) 떠 있던 배너가 줄로 · 판을 접으면 다시 뜬다 — 창이 닫혀 있으면 안 미룬다(기준선)")
    func miniGameRoundDefersThroughLedger() {
        let timers = MbpTimers()
        let store = mbpStore("minigame", timers: timers)
        store.megaphoneBanner.presentOwn(body: "판 전에 뜬 배너", senderName: "나")
        let shown = store.megaphoneBanner.current?.megaphoneID
        #expect(shown != nil)
        // 기준선: 창이 닫혀 있으면 장부가 열려도 미루지 않는다.
        store.isMiniGamePanelVisible = false
        store.beginMiniGameLiveRound(kind: .timingBar)
        #expect(store.megaphoneBanner.current?.megaphoneID == shown, "창이 닫혀 있는데 미뤘다")
        store.settleMiniGameLiveRound()

        store.isMiniGamePanelVisible = true
        store.beginMiniGameLiveRound(kind: .timingBar)
        #expect(store.megaphoneBanner.current == nil, "미니게임 판이 열렸는데 배너가 그대로다")
        #expect(store.megaphoneBanner.queue.first?.megaphoneID == shown)
        store.settleMiniGameLiveRound()
        #expect(store.megaphoneBanner.current?.megaphoneID == shown, "판을 접었는데 배너가 안 돌아왔다")
    }

    @Test("미룸 표: 오목·체스 playing · 테트리스 countdown/playing · 미니게임 판 — 로비·결과·준비는 안 미룬다")
    func deferralTable() {
        func d(_ g: GomokuPhase = .lobby, _ c: ChessPhase = .lobby, _ t: TetrisDuelPhase = .lobby, _ m: Bool = false) -> Bool {
            MegaphoneBannerDeferral.isDeferred(gomoku: g, chess: c, tetris: t, miniGameRoundLive: m)
        }
        #expect(!d())
        #expect(d(.playing) && !d(.result))
        #expect(d(.lobby, .playing) && !d(.lobby, .result))
        #expect(d(.lobby, .lobby, .countdown) && d(.lobby, .lobby, .playing))
        #expect(!d(.lobby, .lobby, .ready) && !d(.lobby, .lobby, .finished))
        #expect(d(.lobby, .lobby, .lobby, true))
    }

    // MARK: 소스 계약(주석을 걷고 잰다)

    @Test("배선: AppDelegate 가 오버레이 컨트롤러를 만든 뒤 배너 컨트롤러를 세워 start 한다 · 진짜 문은 팝오버 · 동작 줄이기를 읽는다")
    func wiringSourceContract() throws {
        let app = try mbpSource("Sources/check/CheckApp.swift")
        let launch = try #require(mbpBody(app, after: "func applicationDidFinishLaunching"), "시작 함수를 못 찾았다")
        let overlay = try #require(launch.range(of: "overlayController = CheckOverlayController("), "전제: 오버레이 컨트롤러 생성")
        let call = try #require(launch.range(of: "wireMegaphoneBanner()"), "시작 함수가 배너 배선을 안 부른다")
        #expect(overlay.upperBound <= call.lowerBound, "배너 배선이 오버레이 컨트롤러보다 먼저다")
        let wire = try #require(mbpBody(app, after: "private func wireMegaphoneBanner()"))
        #expect(wire.contains("MegaphoneBannerWindowController(store: store)") && wire.contains(".start()")
                && wire.contains("megaphoneBannerController = controller"), "배선 함수가 컨트롤러를 세워 쥐지 않는다")

        let window = try mbpSource("Sources/check/CheckMegaphoneBannerWindow.swift")
        let live = try #require(mbpBody(window, after: "static var live: Hooks"))
        #expect(live.contains("WindowTopAnchor.presentMenuPopover()"), "진짜 [답장] 문이 팝오버를 안 띄운다")
        #expect(live.contains("accessibilityDisplayShouldReduceMotion"), "동작 줄이기를 안 읽는다")
        #expect(live.contains("NSEvent.mouseLocation") && live.contains("visibleFrame"), "마우스 화면 · 보이는 틀을 안 읽는다")
        let view = try #require(mbpBody(window, after: "struct MegaphoneBannerView: View"))
        #expect(view.contains(".checkTooltipLayer()"), "배너 루트에 말풍선 레이어가 없다")
        #expect(view.contains(".lineLimit(MegaphoneBannerLayout.bodyLineLimit)") && MegaphoneBannerLayout.bodyLineLimit == 4)
        let ensure = try #require(mbpBody(window, after: "private func ensurePanel()"))
        #expect(ensure.contains("self?.reply()") && ensure.contains("self?.close()") && ensure.contains("self?.hoverChanged(inside)"),
                "카드의 [답장] · [닫기] · 호버가 컨트롤러 문에 안 닿는다")
        // 기준선: 판 장부가 바뀌는 자리에서 미룸을 알린다(관찰 밖 값).
        let store = try mbpSource("Sources/check/WorkTimerStore.swift")
        let ledger = try #require(mbpBody(store, after: "var miniGameLiveRound: MiniGameLiveRound?"))
        #expect(ledger.contains("megaphoneBannerDeferralMayHaveChanged()"))
    }
}
